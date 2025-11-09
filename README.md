# EC2 Instance Stop/Start Lambda Function

This Lambda function stops or starts (resumes) EC2 instances that have the tag `office-hours` when triggered by EventBridge.

## Overview

The function supports two operations:
- **Stop**: Searches for all running EC2 instances with the tag key `office-hours` and stops them
- **Start/Resume**: Searches for all stopped EC2 instances with the tag key `office-hours` and starts them

The function:
- Searches for EC2 instances with the tag key `office-hours` based on the action (stop or start)
- Performs the requested operation (stop or start)
- Returns a summary of the processed instances

## Prerequisites

- AWS account with appropriate permissions
- EC2 instances tagged with `office-hours` tag key
- Lambda function with IAM role that has EC2 permissions

## IAM Permissions Required

The Lambda execution role needs the following permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:StopInstances",
                "ec2:StartInstances"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
```

## Deployment

1. Package the Lambda function:
   ```bash
   pip install -r requirements.txt -t .
   zip -r lambda_function.zip lambda_function.py boto3* botocore*
   ```

2. Create Lambda function in AWS Console or using AWS CLI:
   ```bash
   aws lambda create-function \
     --function-name ec2-office-hours-control \
     --runtime python3.11 \
     --role arn:aws:iam::YOUR_ACCOUNT:role/lambda-ec2-role \
     --handler lambda_function.lambda_handler \
     --zip-file fileb://lambda_function.zip \
     --timeout 60
   ```

3. Create EventBridge rules to trigger the function:

   **Stop instances (e.g., end of day):**
   ```bash
   aws events put-rule \
     --name stop-ec2-office-hours-schedule \
     --schedule-expression "cron(0 18 ? * MON-FRI *)" \
     --description "Stop EC2 instances with office-hours tag at 6 PM weekdays"
   ```

   **Start instances (e.g., start of day):**
   ```bash
   aws events put-rule \
     --name start-ec2-office-hours-schedule \
     --schedule-expression "cron(0 9 ? * MON-FRI *)" \
     --description "Start EC2 instances with office-hours tag at 9 AM weekdays"
   ```

4. Add Lambda permissions for EventBridge:
   ```bash
   # Permission for stop rule
   aws lambda add-permission \
     --function-name ec2-office-hours-control \
     --statement-id allow-eventbridge-stop \
     --action lambda:InvokeFunction \
     --principal events.amazonaws.com \
     --source-arn arn:aws:events:REGION:ACCOUNT:rule/stop-ec2-office-hours-schedule
   
   # Permission for start rule
   aws lambda add-permission \
     --function-name ec2-office-hours-control \
     --statement-id allow-eventbridge-start \
     --action lambda:InvokeFunction \
     --principal events.amazonaws.com \
     --source-arn arn:aws:events:REGION:ACCOUNT:rule/start-ec2-office-hours-schedule
   ```

5. Add Lambda as target to EventBridge rules:
   ```bash
   # Stop rule target (no payload needed, defaults to stop)
   aws events put-targets \
     --rule stop-ec2-office-hours-schedule \
     --targets "Id=1,Arn=arn:aws:lambda:REGION:ACCOUNT:function:ec2-office-hours-control"
   
   # Start rule target (with action payload)
   aws events put-targets \
     --rule start-ec2-office-hours-schedule \
     --targets "Id=1,Arn=arn:aws:lambda:REGION:ACCOUNT:function:ec2-office-hours-control,Input={\"action\":\"start\"}"
   ```

## Tagging EC2 Instances

To tag your EC2 instances so they are stopped by this function:

```bash
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=office-hours,Value=true
```

## Usage

### Stop Instances

Stop all running instances with `office-hours` tag (default behavior):

```bash
aws lambda invoke \
  --function-name ec2-office-hours-control \
  --payload '{}' \
  response.json
```

Or explicitly specify stop action:

```bash
aws lambda invoke \
  --function-name ec2-office-hours-control \
  --payload '{"action": "stop"}' \
  response.json
```

### Start/Resume Instances

Start all stopped instances with `office-hours` tag:

```bash
aws lambda invoke \
  --function-name ec2-office-hours-control \
  --payload '{"action": "start"}' \
  response.json
```

Or use "resume" (same as "start"):

```bash
aws lambda invoke \
  --function-name ec2-office-hours-control \
  --payload '{"action": "resume"}' \
  response.json
```

## Event Payload Format

The Lambda function accepts the following event payload:

```json
{
  "action": "stop"  // Optional: "stop" (default), "start", or "resume"
}
```

- If `action` is not provided or is `"stop"`: Stops all running instances with `office-hours` tag
- If `action` is `"start"` or `"resume"`: Starts all stopped instances with `office-hours` tag

## Notes

- The function only operates on instances that are in the appropriate state:
  - **Stop**: Only stops instances currently in "running" state
  - **Start**: Only starts instances currently in "stopped" state
- EC2 instances don't have a "pause" state - this function stops them
- The function uses the tag key `office-hours` - the tag value can be anything (or empty)
- You can use the same Lambda function for both stop and start operations by passing different event payloads
