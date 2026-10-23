# Move existing Prod Slack webhook secret state into alerting-slack-notifier module.
# This prevents destroy/recreate and preserves the out-of-band Slack webhook value.

moved {
  from = aws_secretsmanager_secret.prod_alerting_slack_webhook[0]
  to   = module.prod_alerting_slack_notifier[0].aws_secretsmanager_secret.slack_webhook
}
