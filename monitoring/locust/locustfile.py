import os
import random
from urllib.parse import quote

from locust import HttpUser, between, task


def env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in ("1", "true", "yes", "y")


def env_list(name: str, default: str) -> list[str]:
    value = os.getenv(name, default)
    return [item.strip() for item in value.split(",") if item.strip()]


class MomentLoadTestUser(HttpUser):
    """
    MoMent M4-PERF-01 Locust scenario.

    Purpose:
    - Not for maximum performance tuning.
    - Used to verify whether Grafana / CloudWatch metrics change under load.
    - Dev ALB is the primary target.
    - Data-changing APIs such as application creation, payment, bookmark creation are excluded.
    """

    wait_time = between(
        float(os.getenv("MOMENT_WAIT_MIN", "1")),
        float(os.getenv("MOMENT_WAIT_MAX", "3")),
    )

    # Default paths can be overridden by environment variables if actual API paths differ.
    home_path = os.getenv("MOMENT_HOME_PATH", "/programs/home")
    program_list_path = os.getenv("MOMENT_PROGRAM_LIST_PATH", "/programs")
    program_detail_path_template = os.getenv(
        "MOMENT_PROGRAM_DETAIL_PATH_TEMPLATE",
        "/programs/{id}",
    )
    search_path_template = os.getenv(
        "MOMENT_SEARCH_PATH_TEMPLATE",
        "/programs/search?keyword={keyword}",
    )
    availability_path_template = os.getenv(
        "MOMENT_AVAILABILITY_PATH_TEMPLATE",
        "/programs/{id}/availability",
    )

    # Recommendation is disabled by default because it may call AI/external APIs or incur cost.
    include_recommendation = env_bool("MOMENT_INCLUDE_RECOMMENDATION", False)
    recommendation_path = os.getenv("MOMENT_RECOMMENDATION_PATH", "/recommendations")

    program_ids = env_list("MOMENT_PROGRAM_IDS", "44,40,45,5,36")
    search_keywords = env_list("MOMENT_SEARCH_KEYWORDS", "교육,박물관,양천구")

    def on_start(self):
        self.headers = {}

        token = os.getenv("MOMENT_AUTH_TOKEN")
        if token:
            self.headers["Authorization"] = f"Bearer {token}"

    def safe_get(self, path: str, name: str, expected_statuses: tuple[int, ...] = (200,)):
        if not path:
            return
        with self.client.get(
            path,
            name=name,
            headers=self.headers,
            catch_response=True,
        ) as response:
            if response.status_code in expected_statuses:
                response.success()
                return
            response.failure(
                f"Unexpected status code: {response.status_code}, path={path}"
            )

    @task(1)
    def health(self):
        self.safe_get("/health", name="GET health")

    @task(1)
    def actuator_health(self):
        self.safe_get("/actuator/health", name="GET actuator/health")

    @task(3)
    def home(self):
        self.safe_get("/programs/home", name="GET home")

    @task(3)
    def program_list(self):
        self.safe_get("/programs", name="GET program list")

    @task(1)
    def program_list_urgent(self):
        self.safe_get("/programs?status=RECRUITING&filter=urgent", name="GET program list urgent")

    @task(1)
    def program_list_free(self):
        self.safe_get("/programs?status=RECRUITING&filter=free", name="GET program list free")

    @task(1)
    def program_list_online(self):
        self.safe_get("/programs?status=RECRUITING&filter=online", name="GET program list online")

    @task(1)
    def program_list_public(self):
        self.safe_get("/programs?status=RECRUITING&filter=public", name="GET program list public")

    @task(4)
    def program_detail(self):
        program_id = random.choice(self.program_ids)
        path = f"/programs/{quote(program_id)}"
        self.safe_get(path, name="GET program detail")