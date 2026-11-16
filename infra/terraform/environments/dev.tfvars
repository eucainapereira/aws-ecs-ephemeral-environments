aws_region             = "us-east-2"
project_name           = "aws-ecs-ephemeral-environments"
ecr_repository_name    = "app"
environment            = "dev"
is_ephemeral           = true
create_shared_resources = true
vpc_cidr               = "10.10.0.0/16"
task_cpu               = 256
task_memory            = 512
desired_count          = 0
log_retention_days     = 14

