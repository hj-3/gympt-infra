locals {
  name_prefix = "${var.project_name}-${var.env}"

  tables = {
    workout_sessions = {
      hash_key  = "userId"
      range_key = "sessionId"
      attributes = [
        { name = "userId", type = "S" },
        { name = "sessionId", type = "S" },
        { name = "completedAt", type = "S" }
      ]
      gsi = [{
        name            = "CompletedAtIndex"
        hash_key        = "userId"
        range_key       = "completedAt"
        projection_type = "ALL"
      }]
    }
    posture_events = {
      hash_key  = "sessionId"
      range_key = "timestamp"
      attributes = [
        { name = "sessionId", type = "S" },
        { name = "timestamp", type = "S" },
        { name = "userId", type = "S" }
      ]
      gsi = [{
        name            = "UserIdIndex"
        hash_key        = "userId"
        range_key       = "timestamp"
        projection_type = "ALL"
      }]
    }
    wearable_events = {
      hash_key  = "userId"
      range_key = "timestamp"
      attributes = [
        { name = "userId", type = "S" },
        { name = "timestamp", type = "S" }
      ]
      gsi = []
    }
    agent_interactions = {
      hash_key  = "userId"
      range_key = "interactionId"
      attributes = [
        { name = "userId", type = "S" },
        { name = "interactionId", type = "S" },
        { name = "createdAt", type = "S" }
      ]
      gsi = [{
        name            = "CreatedAtIndex"
        hash_key        = "userId"
        range_key       = "createdAt"
        projection_type = "ALL"
      }]
    }
  }
}

resource "aws_dynamodb_table" "tables" {
  for_each = local.tables

  name         = "${local.name_prefix}-${each.key}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = each.value.hash_key
  range_key    = each.value.range_key

  dynamic "attribute" {
    for_each = each.value.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = each.value.gsi
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = global_secondary_index.value.projection_type
    }
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(
    var.common_tags,
    {
      Name  = "${local.name_prefix}-${each.key}"
      Table = each.key
    }
  )
}
