provider "aws" {
  region     = "us-east-1"
  access_key = ""
  secret_key = ""
}

#---------------------------------------------------------CREATING S3 BUCKET--------------------------------------------------------------
resource "aws_s3_bucket" "resume_website" {
  bucket = "automationcrc"
}

resource "aws_s3_bucket_website_configuration" "resume_website" {
  bucket = aws_s3_bucket.resume_website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_acl" "resume_website" {
  depends_on = [
    aws_s3_bucket_ownership_controls.resume_website,
    aws_s3_bucket_public_access_block.resume_website,
  ]

  bucket = aws_s3_bucket.resume_website.id
  acl    = "public-read"
}

resource "aws_s3_bucket_public_access_block" "resume_website" {
  bucket = aws_s3_bucket.resume_website.bucket

  block_public_acls   = false
  ignore_public_acls  = false
  block_public_policy = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "resume_website" {
  bucket = aws_s3_bucket.resume_website.bucket

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_policy" "resume_website_policy" {
  bucket = aws_s3_bucket.resume_website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadForGetBucketObjects"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.resume_website.arn}/*"
      }
    ]
  })
}
#--------------------------------------------------------------------------------Creating DynamoDB Table------------------------------------------------------------
resource "aws_dynamodb_table" "dynamodb_table" {
  name           = "automationtestcrc"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled        = true
  }
}

resource "aws_dynamodb_table_item" "initial_item" {
  table_name = aws_dynamodb_table.dynamodb_table.name
  hash_key   = "id"

  item = <<ITEM
{
  "id": {"S": "0"},
  "views": {"N": "0"}
}
ITEM
}
#------------------------------------------------------------------------------------Lambda Function-----------------------------------------------------------------
# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_exec" {
  name = "automationtestcrcrole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_lambda_function" "automationcrclambdafunction" {
  filename          = data.archive_file.zip.output_path
  source_code_hash  = data.archive_file.zip.output_base64sha256
  function_name     = "automationcrclambdafunction"
  role              = aws_iam_role.lambda_exec.arn
  handler           = "automationcrclambdafunction.lambda_handler"
  runtime           = "python3.12"
  timeout           = 10
}

data "archive_file" "zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/"
  output_path = "${path.module}/packedlambda.zip"
}

resource "aws_iam_policy" "iam_policy_for_resume_project" {
  name        = "aws_iam_policy_for_terraform_resume_project_policy"
  path        = "/"
  description = "AWS IAM Policy for managing the resume project role"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:::*"
        Effect   = "Allow"
      },
      {
        Effect   = "Allow"
        Action   = [
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = "arn:aws:dynamodb:::table/automationtestcrc"
      }
    ]
  })
}
#-----------------------------------------------------------------------------------API Gateway-----------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "visitor_count_api" {
  name        = "VisitorCountApi"
  description = "API for Visitor Count"
}

resource "aws_api_gateway_method" "root_method" {
  rest_api_id   = aws_api_gateway_rest_api.visitor_count_api.id
  resource_id   = aws_api_gateway_rest_api.visitor_count_api.root_resource_id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration_response" "root_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.visitor_count_api.id
  resource_id = aws_api_gateway_rest_api.visitor_count_api.root_resource_id
  http_method = aws_api_gateway_method.root_method.http_method
  status_code = "200"
  content_handling = "CONVERT_TO_TEXT"

  response_templates = {
    "application/json" = ""
  }

  depends_on = [aws_api_gateway_integration.root_integration]  # Ensure integration is created before response
}

resource "aws_api_gateway_integration" "root_integration" {
  rest_api_id             = aws_api_gateway_rest_api.visitor_count_api.id
  resource_id             = aws_api_gateway_rest_api.visitor_count_api.root_resource_id
  http_method             = aws_api_gateway_method.root_method.http_method
  type                    = "AWS"  # Use AWS_PROXY if integrating with Lambda
  integration_http_method = "POST"
  uri                     = aws_lambda_function.automationcrclambdafunction.invoke_arn
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_templates = {
    "application/json" = jsonencode({
      # Define request template if needed
    })
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.visitor_count_api.id
  stage_name  = "prod"

  depends_on = [
    aws_api_gateway_integration_response.root_integration_response,
    aws_api_gateway_method_response.visitor_count_method_response,
    aws_api_gateway_integration.root_integration
  ]
}



resource "aws_api_gateway_method_response" "visitor_count_method_response" {
  rest_api_id = aws_api_gateway_rest_api.visitor_count_api.id
  resource_id = aws_api_gateway_rest_api.visitor_count_api.root_resource_id
  http_method             = aws_api_gateway_method.root_method.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
}


resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.automationcrclambdafunction.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.visitor_count_api.execution_arn}/*/*"
}

#---------------------------------------------------------------------ACM Certificate--------------------------------------------------------------------
resource "aws_acm_certificate" "example" {
  domain_name       = "asif-khan.click"
  validation_method = "DNS"
}

data "aws_route53_zone" "example" {
  name         = "asif-khan.click"
  private_zone = false
}

resource "aws_route53_record" "example" {
  for_each = {
    for dvo in aws_acm_certificate.example.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.example.zone_id
}

resource "aws_acm_certificate_validation" "example" {
  certificate_arn         = aws_acm_certificate.example.arn
  validation_record_fqdns = [for record in aws_route53_record.example : record.fqdn]
}

