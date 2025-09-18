# CloudWatch Dashboard for the project
# Creates a simple dashboard with CPU from EC2 and Memory from CWAgent

locals {
  dashboard_name = "${var.project_name}-dashboard"
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = [
      {
        "type" : "text",
        "x" : 0, "y" : 0, "width" : 24, "height" : 3,
        "properties" : {
          "markdown" : "# ${var.project_name} Dashboard\nVisual overview for EC2 Docker host. CPU from AWS/EC2, memory from CWAgent."
        }
      },
      {
        "type" : "metric",
        "x" : 0, "y" : 3, "width" : 12, "height" : 6,
        "properties" : {
          "metrics" : [
            [ "AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.main.id ]
          ],
          "view" : "timeSeries",
          "stacked" : false,
          "region" : var.aws_region,
          "period" : 300,
          "stat" : "Average",
          "title" : "EC2 CPUUtilization (%)"
        }
      },
      {
        "type" : "metric",
        "x" : 12, "y" : 3, "width" : 12, "height" : 6,
        "properties" : {
          "metrics" : [
            [ "CWAgent", "mem_used_percent", "InstanceId", aws_instance.main.id ]
          ],
          "view" : "timeSeries",
          "stacked" : false,
          "region" : var.aws_region,
          "period" : 300,
          "stat" : "Average",
          "title" : "Memory used % (CWAgent)",
          "yAxis" : { "left" : { "min" : 0, "max" : 100 } }
        }
      }
    ]
  })
}
