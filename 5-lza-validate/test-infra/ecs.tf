# ─────────────────────────────────────────────────────────────────────────────
# ECS Fargate in the workload account — the ingress backend + the egress probe.
#   - "web" (nginx) serves :80 → the ingress test target
#   - "egress-probe" curls an ALLOWED SNI and a DENIED site every 30s → egress test
# Image is pulled from Docker Hub (NFW-allowed); see variables.tf.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "test" {
  provider = aws.staging
  name     = "${var.prefix}-stg-network-test"

  setting {
    name  = "containerInsights"
    value = "disabled" # cost-conscious for a throwaway smoke test
  }

  tags = merge(var.tags, { Name = "${var.prefix}-stg-network-test" })
}

resource "aws_cloudwatch_log_group" "ecs" {
  provider          = aws.staging
  name              = "/ecs/${var.prefix}-stg-network-test"
  retention_in_days = 1
  tags              = var.tags
}

# --- Task execution role (pulls image, writes CW Logs) ---
resource "aws_iam_role" "ecs_execution" {
  provider = aws.staging
  name     = "${var.prefix}-stg-net-test-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  provider   = aws.staging
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- ECS task security group ---
resource "aws_security_group" "ecs_tasks" {
  provider    = aws.staging
  name        = "${var.prefix}-stg-net-test-ecs"
  description = "ECS tasks: HTTP:80 from internal ALB; all egress (image pull + egress probe)"
  vpc_id      = data.aws_vpc.staging.id

  ingress {
    description     = "HTTP from internal ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.internal_alb.id]
  }

  egress {
    description = "All egress - Docker Hub image pull + CW Logs + egress probe (via TGW NFW NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.prefix}-stg-net-test-ecs" })
}

# --- Task definition ---
resource "aws_ecs_task_definition" "test" {
  provider                 = aws.staging
  family                   = "${var.prefix}-stg-network-test"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([
    {
      name      = "web"
      image     = var.web_image
      essential = true
      portMappings = [{
        containerPort = 80
        protocol      = "tcp"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "web"
        }
      }
    },
    # Egress probe: proves the NFW allow-path (AWS SNI) AND the default-deny path
    # (arbitrary site). essential=false so a probe hiccup never kills the web
    # container that the ingress test depends on.
    {
      name       = "egress-probe"
      image      = var.egress_probe_image
      essential  = false
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "while true; do echo \"[$(date -u +%%FT%%TZ)] egress probe\"; printf '  amazonaws (ALLOW): '; curl -s -m 8 -o /dev/null -w 'HTTP %%{http_code} in %%{time_total}s\\n' https://kms.${var.region}.amazonaws.com/ || echo 'FAIL (unexpected - allow path broken)'; printf '  example.com (DENY): '; curl -s -m 8 -o /dev/null -w 'HTTP %%{http_code} in %%{time_total}s\\n' https://example.com/ || echo 'blocked (expected - NFW default-deny)'; sleep 30; done"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "egress"
        }
      }
    }
  ])

  tags = var.tags
}

# --- Service ---
resource "aws_ecs_service" "test" {
  provider        = aws.staging
  name            = "${var.prefix}-stg-network-test"
  cluster         = aws_ecs_cluster.test.id
  task_definition = aws_ecs_task_definition.test.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.staging_private.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "web"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.internal_https]
  tags       = merge(var.tags, { Name = "${var.prefix}-stg-network-test" })
}
