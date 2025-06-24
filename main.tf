# Configure the AWS provider to use us-east-1 region and a named profile
provider "aws" {
  region  = "us-east-1"
  profile = "DevOps-2402"
}

# Create a Secrets Manager secret named "my_secret"
resource "aws_secretsmanager_secret" "my_secret" {
  name = "my_secret"
}

# Set the value of the secret to "password123!"
resource "aws_secretsmanager_secret_version" "my_secret" {
  secret_id     = aws_secretsmanager_secret.my_secret.id
  secret_string = "password123!"
}

# Create an IAM role that Lambda can assume
resource "aws_iam_role" "lambda_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach AWS managed Lambda execution policy to the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Allow the Lambda role to access the Secrets Manager secret
resource "aws_iam_role_policy" "secrets_access" {
  name = "lambda_secrets_access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = aws_secretsmanager_secret.my_secret.arn
    }]
  })
}

# Deploy the Lambda function with the zipped source code and IAM role
resource "aws_lambda_function" "my_lambda" {
  filename         = "lambda_function_payload.zip"
  function_name    = "my_lambda_function"
  handler          = "index.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
}

# Create an API Gateway REST API named "hello-api"
resource "aws_api_gateway_rest_api" "api" {
  name        = "hello-api"
  description = "API Gateway triggering Lambda on GET /hello"
}

# Create a resource at path /hello under the API
resource "aws_api_gateway_resource" "hello_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "hello"
}

# Define a GET method on the /hello resource with IAM authentication
resource "aws_api_gateway_method" "get_hello" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hello_resource.id
  http_method   = "GET"
  authorization = "AWS_IAM"  # Require AWS credentials for access
}

# Integrate the GET method with the Lambda function using proxy integration
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.hello_resource.id
  http_method             = aws_api_gateway_method.get_hello.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.my_lambda.invoke_arn
}

# Allow API Gateway to invoke the Lambda function
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/dev/GET/hello"
}

# Deploy the API Gateway changes (creates a deployment version)
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
}

# Create a stage named "dev" for the API deployment
resource "aws_api_gateway_stage" "api_stage" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  stage_name    = "dev"
}

# Output the full public invoke URL for the /hello endpoint
output "invoke_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.us-east-1.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/hello"
}
