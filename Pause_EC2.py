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
    Lambda function to stop EC2 instances with tag 'office-hours'.
    This function is designed to be triggered by EventBridge at scheduled times.
    
    Note: This function will stop ALL running instances with the 'office-hours' tag,
    including instances that are excluded from the Resume_EC2.py function.
    Excluded instances should be stopped by this function to prevent them from running.
    
    Args:
        event: Event data from EventBridge
        context: Lambda context object
    
    Returns:
        dict: Response with status and details of stopped instances
    """
    try:
        # Find all running EC2 instances with tag 'office-hours'
        logger.info("Searching for EC2 instances with tag 'office-hours'")
        
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
                    'Values': ['running']  # Only stop running instances
                }
            ]
        )
        
        # Extract instance IDs
        instance_ids = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_ids.append(instance['InstanceId'])
                logger.info(f"Found instance: {instance['InstanceId']} - {instance.get('Tags', [])}")
        
        if not instance_ids:
            logger.info("No running instances found with tag 'office-hours'")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No running instances found with tag office-hours',
                    'instances_stopped': []
                })
            }
        
        # Stop the instances
        logger.info(f"Stopping {len(instance_ids)} instance(s): {instance_ids}")
        stop_response = ec2_client.stop_instances(InstanceIds=instance_ids)
        
        # Prepare response
        stopped_instances = []
        for instance in stop_response['StoppingInstances']:
            stopped_instances.append({
                'InstanceId': instance['InstanceId'],
                'CurrentState': instance['CurrentState']['Name'],
                'PreviousState': instance['PreviousState']['Name']
            })
        
        logger.info(f"Successfully initiated stop for {len(stopped_instances)} instance(s)")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully stopped {len(stopped_instances)} instance(s)',
                'instances_stopped': stopped_instances
            })
        }
        
    except Exception as e:
        logger.error(f"Error stopping EC2 instances: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Failed to stop EC2 instances',
                'message': str(e)
            })
        }
