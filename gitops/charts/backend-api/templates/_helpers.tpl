{{/*
Expand the name of the chart.
*/}}
{{- define "backend-api.name" -}}
{{- .Chart.Name }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "backend-api.fullname" -}}
{{- .Chart.Name }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "backend-api.labels" -}}
app.kubernetes.io/name: {{ include "backend-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: moment
app.kubernetes.io/managed-by: argocd
environment: {{ .Values.namespace | replace "moment-" "" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "backend-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "backend-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
