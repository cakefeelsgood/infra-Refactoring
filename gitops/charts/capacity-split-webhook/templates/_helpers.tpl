{{- define "capacity-split-webhook.labels" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: moment
app.kubernetes.io/managed-by: argocd
{{- end }}

{{- define "capacity-split-webhook.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.name }}
{{- end }}

{{- define "capacity-split-webhook.certgenHook" -}}
argocd.argoproj.io/hook: {{ . }}
argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
{{- end }}
