# Move existing Dev Slack webhook secret state into alerting-slack-notifier module.
# This prevents destroy/recreate and preserves the out-of-band Slack webhook value.

moved {
  from = aws_secretsmanager_secret.dev_alerting_slack_webhook[0]
  to   = module.dev_alerting_slack_notifier[0].aws_secretsmanager_secret.slack_webhook
}
