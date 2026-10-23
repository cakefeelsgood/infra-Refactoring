import json
import os
import re
import urllib.parse
import urllib.request
from datetime import datetime, timezone

import boto3


s3 = boto3.client("s3")
sqs = boto3.client("sqs")
secretsmanager = boto3.client("secretsmanager")

DEFAULT_HTTP_TIMEOUT_SECONDS = 20
DEFAULT_PAGE_SIZE = 1000
DEFAULT_MAX_PAGES = 30


def lambda_handler(event, context):
    event = event or {}

    raw_bucket_name = os.environ["RAW_BUCKET_NAME"]
    queue_url = os.environ["QUEUE_URL"]
    environment = os.environ.get("ENVIRONMENT", "dev")
    project_name = os.environ.get("PROJECT_NAME", "moment")

    sources = _load_sources()
    sources = _select_sources_for_event(sources, event)

    if not sources:
        raise ValueError(
            "No public data sources configured or selected. "
            "Set DATA_PIPELINE_SOURCES_JSON, DATA_PIPELINE_SOURCES_SECRET_NAME, "
            "legacy PUBLIC_DATA_API_URL, or provide a valid smoke source selector."
        )

    results = []
    for source in sources:
        results.extend(
            _collect_source(
                source=source,
                raw_bucket_name=raw_bucket_name,
                queue_url=queue_url,
                environment=environment,
                project_name=project_name,
                event=event,
            )
        )

    failed_count = len([item for item in results if item["status"] == "FAILED"])
    skipped_count = len([item for item in results if item["status"] == "SKIPPED"])

    return {
        "statusCode": 207 if failed_count else 200,
        "body": {
            "project": project_name,
            "environment": environment,
            "sourceCount": len(sources),
            "objectCount": len(results),
            "failedCount": failed_count,
            "skippedCount": skipped_count,
            "results": results,
        },
    }


DEFAULT_TRIGGER_TYPE = "SCHEDULED_API"
DEFAULT_UPDATE_FREQUENCY = "UNKNOWN"

SUPPORTED_TRIGGER_TYPES = {"SCHEDULED_API", "S3_UPLOAD", "MANUAL", "AD_HOC"}

TRIGGER_TYPE_ALIASES = {
    "SCHEDULED": "SCHEDULED_API",
    "EVENT": "S3_UPLOAD",
    "ON_DEMAND": "AD_HOC",
}

SCHEDULED_COLLECTOR_TRIGGER_TYPES = {"SCHEDULED_API"}


def _load_sources():
    sources_json = os.environ.get("DATA_PIPELINE_SOURCES_JSON", "").strip()
    sources_secret_name = os.environ.get("DATA_PIPELINE_SOURCES_SECRET_NAME", "").strip()
    legacy_api_url = os.environ.get("PUBLIC_DATA_API_URL", "").strip()

    if sources_json:
        parsed = json.loads(sources_json)
        sources = _normalize_sources_payload(parsed, "DATA_PIPELINE_SOURCES_JSON")
        if sources:
            return sources

    if sources_secret_name:
        secret_value = secretsmanager.get_secret_value(SecretId=sources_secret_name)
        secret_string = secret_value.get("SecretString", "")
        parsed = json.loads(secret_string)
        sources = _normalize_sources_payload(parsed, sources_secret_name)
        if sources:
            return sources

    if legacy_api_url:
        return [
            {
                "sourceName": "legacy_public_data_api",
                "url": legacy_api_url,
                "method": "GET",
                "contentType": "application/json",
                "triggerType": DEFAULT_TRIGGER_TYPE,
                "updateFrequency": DEFAULT_UPDATE_FREQUENCY,
                "enabled": True,
            }
        ]

    return []


def _normalize_sources_payload(parsed, source_label):
    if isinstance(parsed, dict) and "sources" in parsed:
        parsed = parsed["sources"]

    if not isinstance(parsed, list):
        raise ValueError(f"{source_label} must be a JSON array or an object with a sources array.")

    normalized_sources = []

    for source in parsed:
        if not source.get("enabled", True):
            continue

        normalized_source = dict(source)
        normalized_source["triggerType"] = _normalize_trigger_type(
            normalized_source.get("triggerType") or normalized_source.get("trigger_type")
        )
        normalized_source["updateFrequency"] = _normalize_update_frequency(
            normalized_source.get("updateFrequency") or normalized_source.get("update_frequency")
        )
        normalized_sources.append(normalized_source)

    return normalized_sources



def _select_sources_for_event(sources, event):
    if not isinstance(event, dict):
        return sources

    smoke = bool(event.get("smoke") or event.get("smokeTest"))
    source_name_filter = event.get("sourceName")
    source_detail_filter = event.get("sourceDetail")

    if smoke and not source_name_filter:
        raise ValueError("smoke source selector requires sourceName to avoid collecting all sources.")

    if not smoke and not source_name_filter and not source_detail_filter:
        return sources

    selected_sources = []
    for source in sources:
        if source_name_filter and source.get("sourceName") != source_name_filter:
            continue

        if source_detail_filter and source.get("sourceDetail", "") != source_detail_filter:
            continue

        selected_source = dict(source)
        selected_source = _apply_smoke_pagination_overrides(selected_source, event)
        selected_sources.append(selected_source)

    if not selected_sources:
        raise ValueError(
            "No source matched smoke selector. "
            f"sourceName={source_name_filter}, sourceDetail={source_detail_filter}"
        )

    print(
        json.dumps(
            {
                "message": "public data collector source selector applied",
                "smoke": smoke,
                "sourceName": source_name_filter,
                "sourceDetail": source_detail_filter,
                "selectedSourceCount": len(selected_sources),
            },
            ensure_ascii=False,
        )
    )

    return selected_sources


def _apply_smoke_pagination_overrides(source, event):
    pagination = dict(source.get("pagination") or {})

    max_pages_override = _get_event_override(event, "maxPages", "smokeMaxPages")
    page_size_override = _get_event_override(event, "pageSize", "smokePageSize")

    if max_pages_override is not None:
        max_pages = int(max_pages_override)
        if max_pages < 1:
            raise ValueError("smoke maxPages must be greater than or equal to 1.")
        pagination["maxPages"] = max_pages

    if page_size_override is not None:
        page_size = int(page_size_override)
        if page_size < 1:
            raise ValueError("smoke pageSize must be greater than or equal to 1.")
        pagination["pageSize"] = page_size
        pagination["sizeParam"] = pagination.get("sizeParam", "numOfRows")

    if pagination:
        source["pagination"] = pagination

    return source


def _get_event_override(event, primary_key, fallback_key):
    if primary_key in event:
        return event[primary_key]

    if fallback_key in event:
        return event[fallback_key]

    return None


def _normalize_operational_metadata(value, default_value):
    if value is None:
        return default_value

    normalized_value = str(value).strip()
    if not normalized_value:
        return default_value

    return normalized_value.upper()


def _normalize_trigger_type(value):
    trigger_type = _normalize_operational_metadata(value, DEFAULT_TRIGGER_TYPE)
    trigger_type = TRIGGER_TYPE_ALIASES.get(trigger_type, trigger_type)

    if trigger_type not in SUPPORTED_TRIGGER_TYPES:
        raise ValueError(
            f"Unsupported triggerType: {trigger_type}. "
            f"Supported values are: {', '.join(sorted(SUPPORTED_TRIGGER_TYPES))}"
        )

    return trigger_type


def _normalize_update_frequency(value):
    return _normalize_operational_metadata(value, DEFAULT_UPDATE_FREQUENCY)


def _build_skipped_result(source, reason):
    source_name = _normalize_source_name(source["sourceName"])
    source_detail = _normalize_source_name(source.get("sourceDetail", ""))
    trigger_type = _normalize_trigger_type(
        source.get("triggerType") or source.get("trigger_type")
    )
    update_frequency = _normalize_update_frequency(
        source.get("updateFrequency") or source.get("update_frequency")
    )

    skipped_result = {
        "status": "SKIPPED",
        "sourceName": source_name,
        "sourceDetail": source_detail,
        "triggerType": trigger_type,
        "updateFrequency": update_frequency,
        "reason": reason,
    }

    print(
        json.dumps(
            {
                "message": "public data source skipped",
                **skipped_result,
            },
            ensure_ascii=False,
        )
    )

    return skipped_result


def _collect_source(source, raw_bucket_name, queue_url, environment, project_name, event):
    trigger_type = _normalize_trigger_type(
        source.get("triggerType") or source.get("trigger_type")
    )

    if trigger_type not in SCHEDULED_COLLECTOR_TRIGGER_TYPES:
        return [
            _build_skipped_result(
                source=source,
                reason="source triggerType is not collected by EventBridge scheduled collector",
            )
        ]

    pagination = source.get("pagination") or {}
    pagination_type = pagination.get("type", "").strip().lower()

    if not pagination_type:
        return [
            _collect_one_request(
                source=source,
                page_context={"pageIndex": 1},
                raw_bucket_name=raw_bucket_name,
                queue_url=queue_url,
                environment=environment,
                project_name=project_name,
                event=event,
            )
        ]

    page_size = int(pagination.get("pageSize", DEFAULT_PAGE_SIZE))
    max_pages = int(pagination.get("maxPages", DEFAULT_MAX_PAGES))
    start_page = int(pagination.get("startPage", 1))

    results = []
    total_count = None

    for page_offset in range(max_pages):
        page_index = page_offset + 1

        if pagination_type in ("seoul-openapi", "index", "range"):
            start_index = page_offset * page_size + 1
            end_index = (page_offset + 1) * page_size
            page_context = {
                "pageIndex": page_index,
                "startIndex": start_index,
                "endIndex": end_index,
                "pageSize": page_size,
            }
        elif pagination_type in ("query", "page"):
            page_no = start_page + page_offset
            page_context = {
                "pageIndex": page_index,
                "pageNo": page_no,
                "pageSize": page_size,
            }
        else:
            raise ValueError(f"Unsupported pagination type: {pagination_type}")

        result = _collect_one_request(
            source=source,
            page_context=page_context,
            raw_bucket_name=raw_bucket_name,
            queue_url=queue_url,
            environment=environment,
            project_name=project_name,
            event=event,
        )
        results.append(result)

        if result["status"] != "SUCCESS":
            break

        if total_count is None:
            total_count = result.get("totalCount")

        if total_count is not None:
            if pagination_type in ("seoul-openapi", "index", "range"):
                if page_context["endIndex"] >= total_count:
                    break
            elif pagination_type in ("query", "page"):
                if page_index * page_size >= total_count:
                    break
        else:
            record_count = result.get("recordCount") or 0
            if record_count < page_size:
                break

    return results


def _collect_one_request(
    source,
    page_context,
    raw_bucket_name,
    queue_url,
    environment,
    project_name,
    event,
):
    source_name = _normalize_source_name(source["sourceName"])
    source_detail = _normalize_source_name(source.get("sourceDetail", ""))
    trigger_type = _normalize_trigger_type(
        source.get("triggerType") or source.get("trigger_type")
    )
    update_frequency = _normalize_update_frequency(
        source.get("updateFrequency") or source.get("update_frequency")
    )

    collected_at_dt = datetime.now(timezone.utc)
    collected_at = _to_iso_z(collected_at_dt)
    compact_timestamp = collected_at_dt.strftime("%Y%m%dT%H%M%SZ")

    try:
        response_payload = _request_public_data(source, page_context)
        body_bytes = response_payload["bodyBytes"]
        response_content_type = response_payload["contentType"]
        extension = _resolve_extension(source, response_content_type)

        record_count = _estimate_record_count(body_bytes, response_content_type, source)
        total_count = _estimate_total_count(body_bytes, response_content_type)

        object_key = _build_object_key(
            source_name=source_name,
            source_detail=source_detail,
            collected_at_dt=collected_at_dt,
            compact_timestamp=compact_timestamp,
            page_context=page_context,
            extension=extension,
        )

        s3.put_object(
            Bucket=raw_bucket_name,
            Key=object_key,
            Body=body_bytes,
            ContentType=response_content_type,
            Metadata={
                "source-name": source_name,
                "source-detail": source_detail or "none",
                "trigger-type": trigger_type,
                "update-frequency": update_frequency,
                "collected-at": collected_at,
                "page-index": str(page_context.get("pageIndex", 1)),
            },
        )

        message = {
            "schemaVersion": "1.0",
            "sourceName": source_name,
            "sourceDetail": source_detail,
            "triggerType": trigger_type,
            "updateFrequency": update_frequency,
            "rawBucketName": raw_bucket_name,
            "rawObjectKey": object_key,
            "collectedAt": collected_at,
            "contentType": response_content_type,
            "recordCount": record_count,
            "totalCount": total_count,
            "environment": environment,
            "page": page_context,
            "contentLength": len(body_bytes),
        }

        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(message, ensure_ascii=False),
        )

        print(
            json.dumps(
                {
                    "message": "public data source collected",
                    "sourceName": source_name,
                    "sourceDetail": source_detail,
                    "triggerType": trigger_type,
                    "updateFrequency": update_frequency,
                    "rawObjectKey": object_key,
                    "recordCount": record_count,
                    "totalCount": total_count,
                    "contentLength": len(body_bytes),
                },
                ensure_ascii=False,
            )
        )

        return {
            "status": "SUCCESS",
            "sourceName": source_name,
            "sourceDetail": source_detail,
            "triggerType": trigger_type,
            "updateFrequency": update_frequency,
            "rawObjectKey": object_key,
            "recordCount": record_count,
            "totalCount": total_count,
            "contentLength": len(body_bytes),
            "page": page_context,
        }

    except Exception as exc:
        failed_key = _build_failed_key(
            source_name=source_name,
            source_detail=source_detail,
            collected_at_dt=collected_at_dt,
            compact_timestamp=compact_timestamp,
            page_context=page_context,
        )

        failure_object = {
            "schemaVersion": "1.0",
            "project": project_name,
            "environment": environment,
            "sourceName": source_name,
            "sourceDetail": source_detail,
            "triggerType": trigger_type,
            "updateFrequency": update_frequency,
            "collectedAt": collected_at,
            "page": page_context,
            "error": str(exc),
            "event": event,
        }

        s3.put_object(
            Bucket=raw_bucket_name,
            Key=failed_key,
            Body=json.dumps(failure_object, ensure_ascii=False).encode("utf-8"),
            ContentType="application/json",
            Metadata={
                "source-name": source_name,
                "source-detail": source_detail or "none",
                "trigger-type": trigger_type,
                "update-frequency": update_frequency,
                "collected-at": collected_at,
                "page-index": str(page_context.get("pageIndex", 1)),
            },
        )

        print(
            json.dumps(
                {
                    "message": "public data source collection failed",
                    "sourceName": source_name,
                    "sourceDetail": source_detail,
                    "triggerType": trigger_type,
                    "updateFrequency": update_frequency,
                    "failedObjectKey": failed_key,
                    "error": str(exc),
                },
                ensure_ascii=False,
            )
        )

        return {
            "status": "FAILED",
            "sourceName": source_name,
            "sourceDetail": source_detail,
            "triggerType": trigger_type,
            "updateFrequency": update_frequency,
            "failedObjectKey": failed_key,
            "error": str(exc),
            "page": page_context,
        }


def _request_public_data(source, page_context):
    url = source.get("url") or source.get("urlTemplate")
    if not url:
        raise ValueError("source url or urlTemplate is required.")

    method = source.get("method", "GET").upper()
    headers = dict(source.get("headers", {}))
    timeout_seconds = int(source.get("timeoutSeconds", DEFAULT_HTTP_TIMEOUT_SECONDS))

    api_key = _resolve_api_key(source)
    url, redacted_url = _apply_api_key(url, source, api_key, headers)
    url, redacted_url = _apply_pagination(url, redacted_url, source, page_context)
    url, redacted_url = _apply_query_params(url, redacted_url, source)

    request = urllib.request.Request(
        url=url,
        method=method,
        headers=headers,
    )

    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        response_content_type = response.headers.get(
            "Content-Type",
            source.get("contentType", "application/octet-stream"),
        )
        body_bytes = response.read()

        return {
            "method": method,
            "redactedUrl": redacted_url,
            "statusCode": response.status,
            "contentType": response_content_type,
            "bodyBytes": body_bytes,
        }


def _resolve_api_key(source):
    secret_name = source.get("apiKeySecretName", "").strip()
    if not secret_name:
        return ""

    secret_value = secretsmanager.get_secret_value(SecretId=secret_name)
    secret_string = secret_value.get("SecretString", "")

    json_key = source.get("apiKeySecretJsonKey", "").strip()
    if json_key:
        parsed = json.loads(secret_string)
        return str(parsed[json_key])

    return secret_string


def _apply_api_key(url, source, api_key, headers):
    if not api_key:
        return url, url

    redacted_url = url
    placeholder = source.get("apiKeyPathPlaceholder", "{apiKey}")
    query_param = source.get("apiKeyQueryParam", "").strip()
    header_name = source.get("apiKeyHeaderName", "").strip()

    if placeholder and placeholder in url:
        encoded_key = urllib.parse.quote(api_key, safe="")
        url = url.replace(placeholder, encoded_key)
        redacted_url = redacted_url.replace(placeholder, "***")

    if query_param:
        url = _set_query_param(url, query_param, api_key)
        redacted_url = _set_query_param(redacted_url, query_param, "***")

    if header_name:
        headers[header_name] = api_key

    if url == redacted_url and not header_name:
        raise ValueError(
            "apiKeySecretName is configured, but no api key placement is configured."
        )

    return url, redacted_url


def _apply_pagination(url, redacted_url, source, page_context):
    replacements = {
        "{startIndex}": page_context.get("startIndex"),
        "{endIndex}": page_context.get("endIndex"),
        "{pageNo}": page_context.get("pageNo"),
        "{pageSize}": page_context.get("pageSize"),
    }

    for placeholder, value in replacements.items():
        if value is not None:
            url = url.replace(placeholder, str(value))
            redacted_url = redacted_url.replace(placeholder, str(value))

    pagination = source.get("pagination") or {}
    pagination_type = pagination.get("type", "").strip().lower()

    if pagination_type in ("query", "page"):
        page_param = pagination.get("pageParam", "pageNo")
        size_param = pagination.get("sizeParam", "numOfRows")

        if page_param and "pageNo" in page_context:
            url = _set_query_param(url, page_param, str(page_context["pageNo"]))
            redacted_url = _set_query_param(redacted_url, page_param, str(page_context["pageNo"]))

        if size_param and "pageSize" in page_context:
            url = _set_query_param(url, size_param, str(page_context["pageSize"]))
            redacted_url = _set_query_param(redacted_url, size_param, str(page_context["pageSize"]))

    return url, redacted_url


def _apply_query_params(url, redacted_url, source):
    query_params = source.get("queryParams") or {}
    for key, value in query_params.items():
        url = _set_query_param(url, key, str(value))
        redacted_url = _set_query_param(redacted_url, key, str(value))

    return url, redacted_url


def _set_query_param(url, key, value):
    parsed_url = urllib.parse.urlparse(url)
    query = dict(urllib.parse.parse_qsl(parsed_url.query, keep_blank_values=True))
    query[key] = value

    return urllib.parse.urlunparse(
        parsed_url._replace(query=urllib.parse.urlencode(query))
    )


def _build_object_key(
    source_name,
    source_detail,
    collected_at_dt,
    compact_timestamp,
    page_context,
    extension,
):
    page_index = int(page_context.get("pageIndex", 1))
    source_prefix = source_name if not source_detail else f"{source_name}/{source_detail}"

    return (
        f"raw/{source_prefix}/"
        f"{collected_at_dt:%Y/%m/%d}/"
        f"{compact_timestamp}-page{page_index:04d}.{extension}"
    )


def _build_failed_key(
    source_name,
    source_detail,
    collected_at_dt,
    compact_timestamp,
    page_context,
):
    page_index = int(page_context.get("pageIndex", 1))
    source_prefix = source_name if not source_detail else f"{source_name}/{source_detail}"

    return (
        f"failed/{source_prefix}/"
        f"{collected_at_dt:%Y/%m/%d}/"
        f"{compact_timestamp}-page{page_index:04d}.json"
    )


def _resolve_extension(source, content_type):
    configured_extension = source.get("contentExtension", "").strip().lstrip(".")
    if configured_extension:
        return configured_extension

    lowered = content_type.lower()

    if "json" in lowered:
        return "json"
    if "xml" in lowered:
        return "xml"
    if "csv" in lowered:
        return "csv"
    if "spreadsheet" in lowered or "excel" in lowered:
        return "xlsx"
    if "zip" in lowered:
        return "zip"

    return "bin"


def _estimate_record_count(body_bytes, content_type, source):
    explicit_count = source.get("recordCount")
    if explicit_count is not None:
        return int(explicit_count)

    lowered = content_type.lower()
    text = _decode_text(body_bytes, source.get("encoding", "utf-8"))

    if "json" in lowered:
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            return 0

        nested_list = _find_first_list(parsed)
        if nested_list is not None:
            return len(nested_list)

        return 1 if parsed else 0

    if "xml" in lowered:
        row_count = len(re.findall(r"<row\b", text, flags=re.IGNORECASE))
        item_count = len(re.findall(r"<item\b", text, flags=re.IGNORECASE))
        return max(row_count, item_count)

    if "csv" in lowered or "text" in lowered:
        lines = [line for line in text.splitlines() if line.strip()]
        return max(len(lines) - 1, 0)

    return 1 if body_bytes else 0


def _estimate_total_count(body_bytes, content_type):
    lowered = content_type.lower()
    text = _decode_text(body_bytes, "utf-8")

    if "json" in lowered:
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            return None

        return _find_total_count_in_json(parsed)

    if "xml" in lowered:
        for tag in ("list_total_count", "totalCount", "total_count", "totalCnt"):
            match = re.search(
                rf"<{tag}>([0-9]+)</{tag}>",
                text,
                flags=re.IGNORECASE,
            )
            if match:
                return int(match.group(1))

    return None


def _find_total_count_in_json(value):
    if isinstance(value, dict):
        for key, child in value.items():
            normalized_key = key.lower()
            if normalized_key in ("list_total_count", "totalcount", "total_count", "totalcnt"):
                try:
                    return int(child)
                except (TypeError, ValueError):
                    return None

        for child in value.values():
            result = _find_total_count_in_json(child)
            if result is not None:
                return result

    if isinstance(value, list):
        for child in value:
            result = _find_total_count_in_json(child)
            if result is not None:
                return result

    return None


def _find_first_list(value):
    if isinstance(value, list):
        return value

    if isinstance(value, dict):
        preferred_keys = ("row", "rows", "items", "item", "data", "results", "records")
        for key in preferred_keys:
            child = value.get(key)
            if isinstance(child, list):
                return child

        for child in value.values():
            result = _find_first_list(child)
            if result is not None:
                return result

    return None


def _decode_text(body_bytes, encoding):
    try:
        return body_bytes.decode(encoding)
    except UnicodeDecodeError:
        return body_bytes.decode(encoding, errors="replace")


def _normalize_source_name(source_name):
    normalized = re.sub(r"[^a-zA-Z0-9_-]+", "_", source_name.strip())
    normalized = normalized.strip("_").lower()

    if not normalized and source_name:
        raise ValueError("sourceName/sourceDetail normalization failed.")

    return normalized


def _to_iso_z(value):
    return value.isoformat().replace("+00:00", "Z")
