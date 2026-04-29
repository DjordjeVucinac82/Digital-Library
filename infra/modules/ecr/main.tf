# ECR module — creates one repository per application image.
# Repositories are shared across environments (images are tagged by environment/commit).
# Lifecycle policy keeps the last 10 tagged images to control storage cost.

resource "aws_ecr_repository" "images" {
  for_each = toset(var.image_names)

  name                 = "digital-library/${each.key}"
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on every push
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "digital-library/${each.key}"
    Environment = var.environment
  }
}

# Keep only the 10 most recent tagged images per repo.
# Untagged images (layer cache) are cleaned up after 1 day.
resource "aws_ecr_lifecycle_policy" "images" {
  for_each   = aws_ecr_repository.images
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 10 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
