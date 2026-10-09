#!/usr/bin/env bash
# Stage 3 - writes the webapp templates and the two environment files.
# Run it from inside dso202-practical-06 (the folder that contains webapp/).
set -e

if [ ! -f webapp/Chart.yaml ]; then
  echo "ERROR: webapp/Chart.yaml not found. cd into dso202-practical-06 first." >&2
  exit 1
fi

mkdir -p webapp/templates/tests environments

# ---------------------------------------------------------------- _helpers.tpl
cat > webapp/templates/_helpers.tpl << 'HELPERS_EOF'
{{/*
_helpers.tpl - named templates shared by every file in templates/.
Files whose names begin with an underscore are never rendered as objects.
*/}}

{{/* webapp.name: the chart name, or nameOverride when set. */}}
{{- define "webapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
webapp.fullname: the base name of every object.
Truncated to 63 characters because Kubernetes label values and DNS labels
are limited to 63 characters. If the release name already contains the
chart name, the release name is used alone to avoid "webapp-dev-webapp".
*/}}
{{- define "webapp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* webapp.chart: "<name>-<version>", used in the helm.sh/chart label. */}}
{{- define "webapp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
webapp.selectorLabels: the labels a Service and a Deployment select on.
These must never change after the first install, because
Deployment.spec.selector is immutable.
*/}}
{{- define "webapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "webapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
webapp.environment: the environment name.
page.environment wins; global.environment (set by a parent chart) is the
fallback. "required" stops rendering with the given message when both are
empty, so no object can be produced without an environment.
*/}}
{{- define "webapp.environment" -}}
{{- required "page.environment must be set (dev, staging or prod)" (.Values.page.environment | default .Values.global.environment) }}
{{- end }}

{{/* webapp.labels: the full recommended label set for every object. */}}
{{- define "webapp.labels" -}}
helm.sh/chart: {{ include "webapp.chart" . }}
{{ include "webapp.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
dso202/environment: {{ include "webapp.environment" . | quote }}
{{- end }}
HELPERS_EOF

# ------------------------------------------------------------- configmap.yaml
cat > webapp/templates/configmap.yaml << 'CONFIGMAP_EOF'
{{- /*
configmap.yaml - the HTML page served by nginx.
*/}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "webapp.fullname" . }}
  labels:
    {{- include "webapp.labels" . | nindent 4 }}
data:
  index.html: |
    <!DOCTYPE html>
    <html>
      <head><title>{{ .Values.page.title }}</title></head>
      <body>
        <h1>{{ .Values.page.title }}</h1>
        <p>{{ .Values.page.message }}</p>
        <p>Environment: {{ include "webapp.environment" . }}</p>
        <p>Release: {{ .Release.Name }} in namespace {{ .Release.Namespace }}</p>
        <p>Chart: {{ include "webapp.chart" . }}, application version {{ .Chart.AppVersion }}</p>
      </body>
    </html>
CONFIGMAP_EOF

# ------------------------------------------------------------ deployment.yaml
cat > webapp/templates/deployment.yaml << 'DEPLOYMENT_EOF'
{{- /*
deployment.yaml - runs replicaCount copies of nginx serving the ConfigMap.
*/}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "webapp.fullname" . }}
  labels:
    {{- include "webapp.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "webapp.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "webapp.labels" . | nindent 8 }}
      annotations:
        # A hash of the rendered ConfigMap. When the page content changes, the
        # hash changes, the Pod template changes, and the Deployment rolls
        # out new Pods. Without it, a ConfigMap change never restarts Pods.
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      containers:
        - name: nginx
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          readinessProbe:
            httpGet:
              path: /
              port: http
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
              readOnly: true
      volumes:
        - name: html
          configMap:
            name: {{ include "webapp.fullname" . }}
DEPLOYMENT_EOF

# --------------------------------------------------------------- service.yaml
cat > webapp/templates/service.yaml << 'SERVICE_EOF'
{{- /*
service.yaml - a stable address for the nginx Pods.
nodePort is emitted only when the type is NodePort AND a port is given.
*/}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "webapp.fullname" . }}
  labels:
    {{- include "webapp.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  selector:
    {{- include "webapp.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      {{- if and (eq .Values.service.type "NodePort") .Values.service.nodePort }}
      nodePort: {{ .Values.service.nodePort }}
      {{- end }}
SERVICE_EOF

# ----------------------------------------------------------------- NOTES.txt
cat > webapp/templates/NOTES.txt << 'NOTES_EOF'
Release {{ .Release.Name }} (revision {{ .Release.Revision }}) is running in namespace {{ .Release.Namespace }}.
Environment: {{ include "webapp.environment" . }}, replicas: {{ .Values.replicaCount }}.
{{- if eq .Values.service.type "NodePort" }}

Open the page from the host:
  curl http://localhost:{{ .Values.service.nodePort }}
{{- else }}

Forward a local port, then open the page:
  kubectl -n {{ .Release.Namespace }} port-forward svc/{{ include "webapp.fullname" . }} 8080:{{ .Values.service.port }}
  curl http://localhost:8080
{{- end }}
NOTES_EOF

# ---------------------------------------------------- tests/test-connection.yaml
cat > webapp/templates/tests/test-connection.yaml << 'TEST_EOF'
{{- /*
tests/test-connection.yaml - run by "helm test". The Pod must exit 0 for the
test to pass. The hook annotation stops it being created by install/upgrade.
*/}}
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "webapp.fullname" . }}-test-connection
  labels:
    {{- include "webapp.labels" . | nindent 4 }}
  annotations:
    helm.sh/hook: test
    helm.sh/hook-delete-policy: before-hook-creation
spec:
  restartPolicy: Never
  containers:
    - name: wget
      image: busybox:1.37
      # A block scalar (|) is used because the script contains ": ", which
      # YAML would otherwise read as a key-value separator.
      command:
        - sh
        - -c
        - |
          wget -qO- http://{{ include "webapp.fullname" . }}:{{ .Values.service.port }} | grep "Environment: {{ include "webapp.environment" . }}"
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          cpu: 50m
          memory: 32Mi
TEST_EOF

# ---------------------------------------------------------- environments/*.yaml
cat > environments/dev.yaml << 'DEV_EOF'
# environments/dev.yaml - overrides for the development release.
replicaCount: 1
page:
  environment: dev
  message: "Development build - not for customers"
service:
  type: NodePort
  # 30081, not 30080: port 30080 is already held by the ingress-nginx
  # controller Service from Assignment 2, and two Services cannot share a NodePort.
  nodePort: 30081
DEV_EOF

cat > environments/prod.yaml << 'PROD_EOF'
# environments/prod.yaml - overrides for the production release.
replicaCount: 3
page:
  environment: prod
  message: "Production"
resources:
  requests:
    cpu: 100m
    memory: 64Mi
  limits:
    cpu: 500m
    memory: 128Mi
PROD_EOF

echo
echo "Done. Files in the chart and environments:"
find webapp environments -type f | sort
