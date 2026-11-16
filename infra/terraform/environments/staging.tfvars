aws_region             = "us-east-2"
project_name           = "aws-ecs-ephemeral-environments"
ecr_repository_name    = "app"
environment            = "staging"
is_ephemeral           = true
create_shared_resources = false
vpc_cidr               = "10.20.0.0/16"
task_cpu               = 256
task_memory            = 512
desired_count          = 0
log_retention_days     = 30

