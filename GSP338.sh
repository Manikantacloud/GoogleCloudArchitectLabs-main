



ZONE="$(gcloud compute instances list --project=$DEVSHELL_PROJECT_ID --format='value(ZONE)' | head -n 1)"


instance_id="$(gcloud compute instances describe video-queue-monitor --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --format='value(id)')"

#TASK 2


gcloud compute instances add-metadata video-queue-monitor \
  --metadata startup-script='#!/bin/bash

# Set environment variables
ZONE="$ZONE"
REGION="${ZONE%-*}"
PROJECT_ID="$DEVSHELL_PROJECT_ID"

# Install Golang
sudo apt update
sudo apt install -y wget git
sudo chmod 777 /usr/local/
wget https://go.dev/dl/go1.19.6.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.19.6.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Install Ops Agent
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install
sudo service google-cloud-ops-agent start

# Create Go working directory and setup GOPATH
mkdir -p /work/go/cache
export GOPATH=/work/go
export GOCACHE=/work/go/cache

# Download Video Queue Go source code
mkdir -p /work/go/video
gsutil cp gs://spls/gsp338/video_queue/main.go /work/go/video/main.go

# Get Cloud Monitoring (Stackdriver) modules
cd /work/go/video
go mod init video
go get go.opencensus.io
go get contrib.go.opencensus.io/exporter/stackdriver

# Set environment variables for the Go application
export MY_PROJECT_ID="$PROJECT_ID"
export MY_GCE_INSTANCE_ID="$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/id)"
export MY_GCE_INSTANCE_ZONE="$ZONE"

# Run the Go application
go run main.go
' --zone "$ZONE"

# Now reset the instance to trigger the startup script
gcloud compute instances reset video-queue-monitor --zone "$ZONE"



#TASK 3

gcloud logging metrics create $METRICS_NAME \
    --description="Metric for hello-app errors" \
    --log-filter='textPayload: "file_format: ([4,8]K).*"'



cat > app-engine-error-percent-policy.json <<EOF_END
{
  "displayName": "quicklab",
  "userLabels": {},
  "conditions": [
    {
      "displayName": "VM Instance - logging/user/big_video_upload_rate",
      "conditionThreshold": {
        "filter": "resource.type = \"gce_instance\" AND metric.type = \"logging.googleapis.com/user/big_video_upload_rate\"",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "crossSeriesReducer": "REDUCE_NONE",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ],
        "comparison": "COMPARISON_GT",
        "duration": "0s",
        "trigger": {
          "count": 1
        },
        "thresholdValue": $ALERT
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "604800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [],
  "severity": "SEVERITY_UNSPECIFIED"
}

EOF_END

