{{- define "batch-job.name" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "batch-job.fullname" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "batch-job.labels" -}}
app.kubernetes.io/name: {{ include "batch-job.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: moment
app.kubernetes.io/managed-by: argocd
environment: {{ .Values.namespace | replace "moment-" "" }}
{{- end }}

{{- define "batch-job.selectorLabels" -}}
app.kubernetes.io/name: {{ include "batch-job.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
