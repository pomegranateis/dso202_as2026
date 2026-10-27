{{/* Labels on every object. The tier label is added per object. */}}
{{- define "tasktracker.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/part-of: tasktracker
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/environment: {{ .Values.environment }}
{{- end }}

{{/* Selector labels: the Assignment 1 tier label plus the release, so two releases never select each other's Pods.
     Usage: include "tasktracker.selectorLabels" (dict "root" . "tier" "backend") */}}
{{- define "tasktracker.selectorLabels" -}}
tier: {{ .tier }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end }}

{{/* Full image reference. Usage: include "tasktracker.image" (dict "root" . "name" "backend") */}}
{{- define "tasktracker.image" -}}
{{ .root.Values.image.repositoryPrefix }}/dso202-{{ .name }}:{{ .root.Values.image.tag | default .root.Chart.AppVersion }}
{{- end }}

{{/* Hash of the rendered config and secret. Put on Pod templates so a config change rolls the Pods
     (Helm's equivalent of Kustomize's generated-name hash). */}}
{{- define "tasktracker.configChecksum" -}}
checksum/config: {{ include (print .Template.BasePath "/configmap.yaml") . | sha256sum }}
checksum/secret: {{ include (print .Template.BasePath "/secret.yaml") . | sha256sum }}
{{- end }}
