{{- define "ai-service.name" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "ai-service.fullname" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "ai-service.labels" -}}
app.kubernetes.io/name: {{ include "ai-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: moment
app.kubernetes.io/managed-by: argocd
environment: {{ .Values.namespace | replace "moment-" "" }}
{{- end }}

{{- define "ai-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ai-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
