terraform {
  backend "s3" {
    bucket         = "moment-team04-dev-terraform-state-611058323802-ap-northeast-3"
    key            = "dev/terraform.tfstate"
    region         = "ap-northeast-3"
    dynamodb_table = "moment-team04-dev-terraform-lock"
    encrypt        = true
    use_lockfile   = true
  }
}
