resource "aws_lb" "delivery_alb" {
  name               = "blue-green-delivery-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name      = "blue-green-delivery-alb"
    Project   = "AWS Blue Green Container Delivery Platform"
    ManagedBy = "Terraform"
  }
}

resource "aws_lb_target_group" "blue_tg" {
  name        = "blue-green-blue-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "blue-green-blue-tg"
  }
}

resource "aws_lb_target_group" "green_tg" {
  name        = "blue-green-green-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "blue-green-green-tg"
  }
}

resource "aws_lb_listener" "production_listener" {
  load_balancer_arn = aws_lb.delivery_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "production_rule" {
  listener_arn = aws_lb_listener.production_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue_tg.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}