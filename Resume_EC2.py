import boto3
import json
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize EC2 client
ec2_client = boto3.client('ec2')

def lambda_handler(event, context):
    """
    Lambda function to start (resume) EC2 instances with tag 'office-hours'.
    This function is designed to be triggered by EventBridge at scheduled times.
    
    Event payload examples:
    - Start all: {} or {"exclude_instance_ids": []}
    - Exclude instances: {"exclude_instance_ids": ["i-1234567890abcdef0", "i-0987654321fedcba0"]}
    
    Args:
        event: Event data from EventBridge (can contain 'exclude_instance_ids' list)
        context: Lambda context object
    
    Returns:
        dict: Response with status and details of started instances
    """
    try:
        # Parse event to get excluded instance IDs
        exclude_instance_ids = []
        if isinstance(event, dict):
            event_data = event
            if 'body' in event and isinstance(event['body'], str):
                try:
                    event_data = json.loads(event['body'])
                except json.JSONDecodeError:
                    event_data = event
            else:
                event_data = event
            
            if 'exclude_instance_ids' in event_data:
                exclude_instance_ids = event_data['exclude_instance_ids']
                if isinstance(exclude_instance_ids, str):
                    # Handle comma-separated string
                    exclude_instance_ids = [id.strip() for id in exclude_instance_ids.split(',')]
                logger.info(f"Excluding {len(exclude_instance_ids)} instance(s) from start: {exclude_instance_ids}")
        
        # Find all stopped EC2 instances with tag 'office-hours'
        logger.info("Searching for stopped EC2 instances with tag 'office-hours'")
        
        # Describe instances with the tag filter
        # Filter by tag KEY 'office-hours' - the tag VALUE can be anything (or empty)
        # Examples: Key=office-hours,Value=true OR Key=office-hours,Value=yes OR Key=office-hours,Value=(empty)
        response = ec2_client.describe_instances(
            Filters=[
                {
                    'Name': 'tag:office-hours',  # Tag KEY must be 'office-hours'
                    'Values': ['*']  # Tag VALUE can be anything - '*' is a wildcard matching any value
                },
                {
                    'Name': 'instance-state-name',
                    'Values': ['stopped']  # Only start stopped instances
                }
            ]
        )
        
        # Extract instance IDs and exclude specified instances
        instance_ids = []
        excluded_count = 0
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                if instance_id in exclude_instance_ids:
                    excluded_count += 1
                    logger.info(f"Excluding instance from start: {instance_id} - {instance.get('Tags', [])}")
                else:
                    instance_ids.append(instance_id)
                    logger.info(f"Found instance: {instance_id} - {instance.get('Tags', [])}")
        
        if not instance_ids:
            if excluded_count > 0:
                logger.info(f"No instances to start after excluding {excluded_count} instance(s)")
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': f'No instances to start after excluding {excluded_count} instance(s)',
                        'instances_started': [],
                        'instances_excluded': excluded_count
                    })
                }
            else:
                logger.info("No stopped instances found with tag 'office-hours'")
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'No stopped instances found with tag office-hours',
                        'instances_started': []
                    })
                }
        
        # Start the instances
        logger.info(f"Starting {len(instance_ids)} instance(s): {instance_ids}")
        start_response = ec2_client.start_instances(InstanceIds=instance_ids)
        
        # Prepare response
        started_instances = []
        for instance in start_response['StartingInstances']:
            started_instances.append({
                'InstanceId': instance['InstanceId'],
                'CurrentState': instance['CurrentState']['Name'],
                'PreviousState': instance['PreviousState']['Name']
            })
        
        logger.info(f"Successfully initiated start for {len(started_instances)} instance(s)")
        
        response_body = {
            'message': f'Successfully started {len(started_instances)} instance(s)',
            'instances_started': started_instances
        }
        
        if excluded_count > 0:
            response_body['instances_excluded'] = excluded_count
            response_body['excluded_instance_ids'] = exclude_instance_ids
        
        return {
            'statusCode': 200,
            'body': json.dumps(response_body)
        }
        
    except Exception as e:
        logger.error(f"Error starting EC2 instances: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Failed to start EC2 instances',
                'message': str(e)
            })
        }

