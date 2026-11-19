# retrieve a hosted zone id from SSM parameter store
hostedzone_id = data.aws_ssm_parameter.hostedzone_id.value

data "aws_ssm_parameter" "hostedzone_id" {
  name = "/${var.project_name}/hostedzone_id"
}