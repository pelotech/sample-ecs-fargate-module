#####
# Cloudwatch
#####yes
resource "aws_cloudwatch_log_group" "main" {
  name              = var.name
  retention_in_days = 14
  tags = {
    Owner       = var.owner
    Environment = var.environment
  }
}

#####
# IAM - Task execution role, needed to pull ECR images etc.
#####
resource "aws_iam_role" "execution" {
  name               = "${var.name}-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
  tags = {
    Owner       = var.owner
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "${var.name}-task-execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.task_execution_permissions.json
}

#####
# IAM - Task role, basic. Append policies to this role for S3, DynamoDB etc.
#####
resource "aws_iam_role" "task" {
  name               = "${var.name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
  tags = {
    Owner       = var.owner
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "log_agent" {
  name   = "${var.name}-log-permissions"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_log_permissions.json
}

resource "aws_iam_role_policy_attachment" "s3_full_permissions" {
  policy_arn = data.aws_iam_policy.s3_full_access.arn
  role       = aws_iam_role.task.id
}


#####
# Security groups
#####
resource "aws_security_group" "lb" {
  vpc_id      = var.vpc_id
  name        = "${var.name}-lb-sg"
  description = "lb service security group"
  tags = {
    Owner       = var.owner
    Environment = var.environment
  }
}

resource "aws_security_group_rule" "lb_whitelist_http" {
  # count = var.enable_https ? 0 : 1
  security_group_id = aws_security_group.lb.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "lb_whitelist_https" {
  # count = var.enable_https ? 1 : 0
  security_group_id = aws_security_group.lb.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "lb_egress_service" {
  security_group_id = aws_security_group.lb.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_security_group" "ecs" {
  vpc_id      = var.vpc_id
  name        = "${var.name}-ecs-service-sg"
  description = "Fargate service security group"
  tags = {
    Owner       = var.owner
    Environment = var.environment
  }
}
resource "aws_security_group_rule" "ecs_whitelist_http" {
  security_group_id        = aws_security_group.ecs.id
  type                     = "ingress"
  from_port                = var.application_port
  to_port                  = var.application_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lb.id
  //  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ecs_egress_service" {
  security_group_id = aws_security_group.ecs.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

#####
# Load Balancer Target group
#####
resource "aws_lb_target_group" "this" {
  name        = "${var.name}-target-${var.application_port}"
  vpc_id      = var.vpc_id
  protocol    = "HTTP"
  port        = var.application_port
  target_type = "ip"
  lifecycle {
    create_before_destroy = true
  }
  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = var.application_port
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200,302,404,401"
  }
  depends_on = [aws_lb.this]
  tags = {
    Owner       = var.owner
    Environment = var.environment
  }
}

resource "aws_lb" "this" {
  name            = var.name
  subnets         = var.public_subnet_ids
  security_groups = [aws_security_group.lb.id]
  tags = {
    Description = var.name
    Owner       = var.owner
    Environment = var.environment
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = "443"
  protocol          = "HTTPS"
  default_action {
    target_group_arn = aws_lb_target_group.this.arn
    type             = "forward"
  }
  certificate_arn = var.acm_ssl_cert_arn
}


resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  execution_role_arn       = aws_iam_role.execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = templatefile(
    "${path.module}/templates/container_definition.json",
    {
      image                      = "${var.image_name}:${var.image_tag}"
      log_name                   = aws_cloudwatch_log_group.main.name
      name                       = var.name
      application_port           = var.application_port
      region                     = var.region
      environment_variables_json = jsonencode(var.environment_variables)
      secrets_from_json          = jsonencode(var.secrets_from)
      command                    = jsonencode(var.task_command)
    }
  )
  tags = {
    Owner       = var.owner
    Environment = var.environment
  }
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  deployment_controller {
    type = "ECS"
  }
  network_configuration {
    assign_public_ip = true
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
  }
  load_balancer {
    container_name   = "app"
    container_port   = var.application_port
    target_group_arn = aws_lb_target_group.this.arn
  }
}
