# How Excluded Instance IDs Work

## Overview

The `Resume_EC2.py` function allows you to exclude specific EC2 instances from being started, even if they have the `office-hours` tag. These excluded instances will remain stopped and will be stopped by `Pause_EC2.py` if they're running.

## How It Works

1. **Function receives event payload** - The Lambda function gets triggered with an event
2. **Parses excluded IDs** - It looks for `exclude_instance_ids` in the event payload
3. **Finds all stopped instances** - Searches for stopped instances with `office-hours` tag
4. **Filters out excluded instances** - Removes excluded instance IDs from the list
5. **Starts remaining instances** - Only starts instances that are NOT in the exclusion list

## Where to Add Excluded Instance IDs

You can add excluded instance IDs in several ways:

### Method 1: EventBridge Rule Configuration (Recommended for Scheduled Tasks)

When setting up an EventBridge rule to trigger the Lambda function, you can pass the excluded instance IDs in the rule's input.

**Using AWS Console:**
1. Go to EventBridge → Rules → Your Resume Rule
2. Click "Edit"
3. Under "Target", expand "Additional settings"
4. In "Configure target input", select "Constant (JSON text)"
5. Enter the JSON:
```json
{
  "exclude_instance_ids": ["i-1234567890abcdef0", "i-0987654321fedcba0"]
}
```

**Using AWS CLI:**
```bash
aws events put-targets \
  --rule start-ec2-office-hours-schedule \
  --targets "Id=1,Arn=arn:aws:lambda:REGION:ACCOUNT:function:resume-ec2-office-hours,Input={\"exclude_instance_ids\":[\"i-1234567890abcdef0\",\"i-0987654321fedcba0\"]}"
```

### Method 2: Manual Lambda Invocation (Testing)

When testing or manually invoking the function:

**Using AWS CLI:**
```bash
aws lambda invoke \
  --function-name resume-ec2-office-hours \
  --payload '{"exclude_instance_ids": ["i-1234567890abcdef0", "i-0987654321fedcba0"]}' \
  response.json
```

**Using AWS Console:**
1. Go to Lambda → Your Function → Test
2. Create a test event with:
```json
{
  "exclude_instance_ids": ["i-1234567890abcdef0", "i-0987654321fedcba0"]
}
```

### Method 3: Comma-Separated String (Alternative Format)

You can also pass instance IDs as a comma-separated string:

```bash
aws lambda invoke \
  --function-name resume-ec2-office-hours \
  --payload '{"exclude_instance_ids": "i-1234567890abcdef0,i-0987654321fedcba0"}' \
  response.json
```

### Method 4: No Exclusions (Start All)

If you don't provide `exclude_instance_ids` or pass an empty array, all stopped instances with the tag will be started:

```bash
aws lambda invoke \
  --function-name resume-ec2-office-hours \
  --payload '{}' \
  response.json
```

Or:
```bash
aws lambda invoke \
  --function-name resume-ec2-office-hours \
  --payload '{"exclude_instance_ids": []}' \
  response.json
```

## Example Scenarios

### Scenario 1: Exclude One Instance
```json
{
  "exclude_instance_ids": ["i-1234567890abcdef0"]
}
```

### Scenario 2: Exclude Multiple Instances
```json
{
  "exclude_instance_ids": [
    "i-1234567890abcdef0",
    "i-0987654321fedcba0",
    "i-abcdef1234567890"
  ]
}
```

### Scenario 3: No Exclusions (Start All)
```json
{}
```

## Event Payload Structure

The function accepts the following event structure:

```json
{
  "exclude_instance_ids": ["instance-id-1", "instance-id-2"]
}
```

**Fields:**
- `exclude_instance_ids` (optional): Array of instance IDs to exclude from starting
  - Can be an array: `["i-123", "i-456"]`
  - Can be a comma-separated string: `"i-123,i-456"`
  - If not provided or empty, all instances will be started

## How to Find Instance IDs

**Using AWS Console:**
1. Go to EC2 → Instances
2. Find your instance
3. Copy the Instance ID (e.g., `i-1234567890abcdef0`)

**Using AWS CLI:**
```bash
aws ec2 describe-instances \
  --filters "Name=tag:office-hours,Values=*" \
  --query "Reservations[*].Instances[*].[InstanceId,Tags[?Key=='Name'].Value|[0]]" \
  --output table
```

## Complete Example: EventBridge Setup with Exclusions

Here's a complete example of setting up an EventBridge rule that excludes specific instances:

```bash
# 1. Create the EventBridge rule
aws events put-rule \
  --name start-ec2-office-hours-schedule \
  --schedule-expression "cron(0 9 ? * MON-FRI *)" \
  --description "Start EC2 instances with office-hours tag at 9 AM weekdays (excluding specific instances)"

# 2. Add Lambda permission
aws lambda add-permission \
  --function-name resume-ec2-office-hours \
  --statement-id allow-eventbridge-start \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:REGION:ACCOUNT:rule/start-ec2-office-hours-schedule

# 3. Add target with excluded instance IDs
aws events put-targets \
  --rule start-ec2-office-hours-schedule \
  --targets "Id=1,Arn=arn:aws:lambda:REGION:ACCOUNT:function:resume-ec2-office-hours,Input={\"exclude_instance_ids\":[\"i-1234567890abcdef0\",\"i-0987654321fedcba0\"]}"
```

## Response Format

When instances are excluded, the response includes:

```json
{
  "message": "Successfully started 2 instance(s)",
  "instances_started": [
    {
      "InstanceId": "i-abc123",
      "CurrentState": "pending",
      "PreviousState": "stopped"
    }
  ],
  "instances_excluded": 1,
  "excluded_instance_ids": ["i-1234567890abcdef0"]
}
```

## Important Notes

1. **Excluded instances are NOT started** - They remain in their current state (stopped)
2. **Pause function stops ALL instances** - `Pause_EC2.py` will stop excluded instances if they're running
3. **Tag still required** - Excluded instances must still have the `office-hours` tag to be found, but they won't be started
4. **Case sensitive** - Instance IDs are case-sensitive, make sure to use exact IDs
5. **No wildcards** - You must specify exact instance IDs, wildcards are not supported


