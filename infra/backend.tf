terraform {
  backend "s3" {
    bucket       = "talk-booking-tfstate-1ca6a67"
    key          = "global/foundation/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
