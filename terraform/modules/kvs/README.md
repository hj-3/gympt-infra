# Kinesis Video Streams (KVS) Module

This module provisions AWS Kinesis Video Streams infrastructure for real-time camera streaming and WebRTC signaling channels for the GYMPT platform.

## Features

- **KVS Streams**: Ingest and store video streams from workout cameras
- **WebRTC Signaling**: Enable real-time bidirectional video communication
- **IRSA Integration**: Secure pod-to-KVS authentication via EKS OIDC
- **Producer/Consumer Roles**: Separate IAM roles for streaming and viewing
- **CloudWatch Monitoring**: Automatic alarms for stream health
- **Configurable Retention**: Customize data retention per stream

## Architecture

```
┌─────────────────┐
│  Camera Pods    │ (Producer)
│  (Streaming NS) │
└────────┬────────┘
         │ IRSA
         ▼
┌─────────────────┐      ┌──────────────────┐
│ KVS Streams     │◄─────┤ WebRTC Signaling │
│ workout-sessions│      │ live-sessions    │
└────────┬────────┘      └────────┬─────────┘
         │                        │
         │ IRSA                   │ IRSA
         ▼                        ▼
┌─────────────────┐      ┌──────────────────┐
│  Viewer Pods    │      │  Live Session    │
│  (API/Frontend) │      │  Pods            │
└─────────────────┘      └──────────────────┘
```

## Usage

### Basic Configuration

```hcl
module "kvs" {
  source = "../../modules/kvs"

  environment            = "dev"
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  kvs_namespace         = "streaming"

  streams = {
    workout-sessions = {
      retention_hours = 24
    }
    pt-live-sessions = {
      retention_hours = 2
    }
  }

  webrtc_channels = {
    live-sessions = {
      enabled = true
    }
  }

  tags = {
    Project = "gympt"
    Team    = "platform"
  }
}
```

### Advanced Configuration

```hcl
module "kvs" {
  source = "../../modules/kvs"

  environment            = "prod"
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  kvs_namespace         = "streaming"

  streams = {
    workout-sessions = {
      retention_hours = 168  # 7 days
    }
    form-analysis = {
      retention_hours = 24
    }
    security-cameras = {
      retention_hours = 720  # 30 days
    }
  }

  webrtc_channels = {
    live-sessions = {
      enabled = true
    }
    pt-consultations = {
      enabled = true
    }
  }

  tags = {
    Project     = "gympt"
    Environment = "prod"
    Compliance  = "HIPAA"
  }
}
```

## Kubernetes Integration

### Producer Service Account (Camera Pods)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kvs-producer-sa
  namespace: streaming
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/dev-kvs-producer-role
```

### Consumer Service Account (Viewer Pods)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kvs-consumer-sa
  namespace: streaming
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/dev-kvs-consumer-role
```

### Pod Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: camera-streamer
  namespace: streaming
spec:
  template:
    spec:
      serviceAccountName: kvs-producer-sa
      containers:
      - name: streamer
        image: gympt/camera-streamer:latest
        env:
        - name: KVS_STREAM_NAME
          value: "dev-workout-sessions"
        - name: AWS_REGION
          value: "ap-northeast-2"
```

## WebRTC Configuration

### STUN/TURN Servers

KVS provides managed STUN/TURN servers via the `GetIceServerConfig` API:

```python
import boto3

kvs_client = boto3.client('kinesisvideo')

# Get signaling channel endpoint
response = kvs_client.get_signaling_channel_endpoint(
    ChannelARN='arn:aws:kinesisvideo:...',
    SingleMasterChannelEndpointConfiguration={
        'Protocols': ['WSS', 'HTTPS'],
        'Role': 'MASTER'
    }
)

# Get ICE server configuration
ice_config = kvs_client.get_ice_server_config(
    ChannelARN='arn:aws:kinesisvideo:...'
)
```

### WebRTC Connection Flow

1. **Master** (PT/Trainer): Connects to signaling channel as MASTER
2. **Viewer** (Client): Connects to signaling channel as VIEWER
3. **Signaling**: Exchange SDP offers/answers via channel
4. **ICE**: Negotiate peer connection using KVS TURN servers
5. **Media**: Establish direct P2P connection when possible

## Streaming from Cameras

### Using AWS SDK (Python)

```python
import boto3
import cv2

kvs_client = boto3.client('kinesisvideo')

# Get data endpoint
response = kvs_client.get_data_endpoint(
    StreamName='dev-workout-sessions',
    APIName='PUT_MEDIA'
)

endpoint = response['DataEndpoint']

# Stream video frames
kvs_media = boto3.client('kinesis-video-media', endpoint_url=endpoint)

with open('video.mkv', 'rb') as f:
    kvs_media.put_media(
        StreamName='dev-workout-sessions',
        FragmentTimecodeType='ABSOLUTE',
        Body=f
    )
```

### Using GStreamer

```bash
gst-launch-1.0 \
  v4l2src device=/dev/video0 ! \
  videoconvert ! \
  x264enc bframes=0 key-int-max=45 bitrate=500 ! \
  video/x-h264,stream-format=avc,alignment=au,profile=baseline ! \
  kvssink \
    stream-name="dev-workout-sessions" \
    storage-size=512 \
    access-key="$AWS_ACCESS_KEY_ID" \
    secret-key="$AWS_SECRET_ACCESS_KEY" \
    aws-region="ap-northeast-2"
```

## Playback and Retrieval

### HLS Streaming

```python
import boto3

kvs_client = boto3.client('kinesisvideo')

# Get HLS streaming endpoint
response = kvs_client.get_data_endpoint(
    StreamName='dev-workout-sessions',
    APIName='GET_HLS_STREAMING_SESSION_URL'
)

endpoint = response['DataEndpoint']

# Get HLS URL
kvs_archived = boto3.client('kinesis-video-archived-media', endpoint_url=endpoint)

hls_url = kvs_archived.get_hls_streaming_session_url(
    StreamName='dev-workout-sessions',
    PlaybackMode='LIVE',
    HLSFragmentSelector={
        'FragmentSelectorType': 'SERVER_TIMESTAMP'
    }
)

print(hls_url['HLSStreamingSessionURL'])
```

### Fragment Retrieval

```python
# Get specific time range
fragments = kvs_archived.list_fragments(
    StreamName='dev-workout-sessions',
    MaxResults=10,
    FragmentSelector={
        'FragmentSelectorType': 'SERVER_TIMESTAMP',
        'TimestampRange': {
            'StartTimestamp': datetime(2026, 5, 19, 10, 0, 0),
            'EndTimestamp': datetime(2026, 5, 19, 11, 0, 0)
        }
    }
)

# Download media
media = kvs_archived.get_media_for_fragment_list(
    StreamName='dev-workout-sessions',
    Fragments=[f['FragmentNumber'] for f in fragments['Fragments']]
)
```

## Monitoring

### CloudWatch Metrics

The module creates alarms for:

- **PutMedia Errors**: Alerts when stream ingestion fails
- **Incoming Bytes**: Alerts when stream data rate drops

Additional available metrics:

```
AWS/KinesisVideo:
- PutMedia.Success
- PutMedia.Latency
- PutMedia.IncomingBytes
- PutMedia.IncomingFrames
- GetMedia.Success
- GetMedia.OutgoingBytes
- GetMedia.OutgoingFrames
- GetMedia.ConnectionErrors
```

### Custom Metrics Dashboard

```hcl
resource "aws_cloudwatch_dashboard" "kvs" {
  dashboard_name = "gympt-kvs-streams"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/KinesisVideo", "PutMedia.IncomingBytes", { stat = "Sum" }],
            [".", "PutMedia.IncomingFrames", { stat = "Sum" }]
          ]
          period = 300
          region = "ap-northeast-2"
          title  = "Stream Ingestion"
        }
      }
    ]
  })
}
```

## Security

### IAM Permissions

**Producer (Camera) Permissions:**
- `kinesisvideo:PutMedia`
- `kinesisvideo:DescribeStream`
- `kinesisvideo:GetDataEndpoint`

**Consumer (Viewer) Permissions:**
- `kinesisvideo:GetMedia`
- `kinesisvideo:GetMediaForFragmentList`
- `kinesisvideo:ListFragments`
- `kinesisvideo:DescribeStream`

### Network Security

- KVS endpoints are public but authenticated via IAM
- Use VPC endpoints for private connectivity (optional)
- WebRTC uses DTLS-SRTP for media encryption
- Signaling channel uses WSS (TLS 1.2+)

### Compliance Considerations

- **Data Retention**: Configure retention based on compliance needs
- **Encryption**: KVS encrypts data at rest using KMS
- **Access Logs**: Enable CloudTrail for API audit logging
- **HIPAA**: KVS is HIPAA-eligible when properly configured

## Cost Optimization

### Pricing Model

- **Data Ingested**: $0.0085/GB
- **Data Consumed**: $0.0085/GB
- **Data Stored**: $0.023/GB-month
- **WebRTC Signaling**: $0.04/1000 messages

### Optimization Strategies

1. **Reduce Retention**: Shorter retention = lower storage costs
2. **Optimize Bitrate**: Balance quality vs bandwidth costs
3. **Fragment Duration**: Longer fragments reduce metadata overhead
4. **On-Demand Playback**: Use HLS instead of continuous GetMedia
5. **Lifecycle Policies**: Move old recordings to S3 for archival

### Cost Monitoring

```bash
# Estimate monthly cost for 100 cameras streaming 8 hours/day
# Bitrate: 2 Mbps, Retention: 24 hours

Ingestion: 100 cameras × 2 Mbps × 8 hrs/day × 30 days × $0.0085/GB
         = 100 × 900 GB × $0.0085
         = $765/month

Storage: 900 GB × 24/720 retention ratio × $0.023/GB-month
       = 30 GB × $0.023
       = $0.69/month

Total: ~$766/month
```

## Troubleshooting

### Common Issues

**1. PutMedia Errors**
```bash
# Check stream status
aws kinesisvideo describe-stream --stream-name dev-workout-sessions

# Verify IAM permissions
aws sts get-caller-identity
aws iam simulate-principal-policy --policy-source-arn <role-arn> \
  --action-names kinesisvideo:PutMedia
```

**2. No Data Flowing**
```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/KinesisVideo \
  --metric-name PutMedia.IncomingBytes \
  --dimensions Name=StreamName,Value=dev-workout-sessions \
  --start-time 2026-05-19T00:00:00Z \
  --end-time 2026-05-19T23:59:59Z \
  --period 3600 \
  --statistics Sum
```

**3. WebRTC Connection Fails**
```python
# Test signaling channel connectivity
import boto3

kvs = boto3.client('kinesisvideo')

response = kvs.describe_signaling_channel(
    ChannelName='dev-live-sessions-signaling'
)

print(response['ChannelInfo']['ChannelStatus'])  # Should be 'ACTIVE'
```

**4. High Latency**
- Check network bandwidth between source and AWS
- Reduce fragment duration (default 2s, try 1s)
- Use regional endpoints closer to source
- Enable timecode mode for better sync

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| environment | Environment name | string | - | yes |
| streams | KVS streams configuration | map(object) | workout-sessions (24h) | no |
| webrtc_channels | WebRTC signaling channels | map(object) | live-sessions | no |
| eks_oidc_provider_arn | EKS OIDC provider ARN | string | - | yes |
| kvs_namespace | Kubernetes namespace | string | streaming | no |
| tags | Common resource tags | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| stream_arns | Map of KVS stream ARNs |
| stream_names | Map of KVS stream names |
| stream_ids | Map of KVS stream IDs |
| signaling_channel_arns | Map of WebRTC signaling channel ARNs |
| signaling_channel_names | Map of WebRTC signaling channel names |
| producer_role_arn | IAM role ARN for producers |
| producer_role_name | IAM role name for producers |
| consumer_role_arn | IAM role ARN for consumers |
| consumer_role_name | IAM role name for consumers |
| cloudwatch_alarm_arns | Map of CloudWatch alarm ARNs |

## References

- [AWS KVS Documentation](https://docs.aws.amazon.com/kinesisvideostreams/)
- [WebRTC Signaling](https://docs.aws.amazon.com/kinesisvideostreams-webrtc-dg/)
- [GStreamer Plugin](https://github.com/awslabs/amazon-kinesis-video-streams-producer-sdk-cpp)
- [IRSA Setup](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
