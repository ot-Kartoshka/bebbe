terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.0"
}

provider "aws" {
  region                      = "eu-central-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    s3       = "http://172.31.24.189:4566"
    lambda   = "http://172.31.24.189:4566"
    iam      = "http://172.31.24.189:4566"
    sqs      = "http://172.31.24.189:4566"
  }
}


resource "aws_s3_bucket" "start" {
  bucket = "s3-start"
}


resource "aws_s3_bucket" "finish" {
  bucket = "s3-finish"
}


resource "aws_s3_bucket_lifecycle_configuration" "start_lifecycle" {
  bucket = aws_s3_bucket.start.id

  rule {
    id     = "delete_after_1_day"
    status = "Enabled"

    expiration {
      days = 1
    }

    filter {}
  }
}



resource "aws_sqs_queue" "myqueue" {
  name = "s3-copy-events"
}


resource "aws_iam_role" "lambda_exec" {
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


resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_policy"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.start.arn,
          "${aws_s3_bucket.start.arn}/*",
          aws_s3_bucket.finish.arn,
          "${aws_s3_bucket.finish.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.myqueue.arn
      }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda/lambda_function.zip"
}


resource "aws_lambda_function" "copy_function" {
  filename         = "${path.module}/lambda/lambda_function.zip"
  function_name    = "s3copy"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      TARGET_BUCKET = aws_s3_bucket.finish.bucket
      QUEUE_URL     = aws_sqs_queue.myqueue.url
    }
  }
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.copy_function.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.start.arn
}

resource "aws_s3_bucket_notification" "start_notification" {
  bucket = aws_s3_bucket.start.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.copy_function.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ""
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}
