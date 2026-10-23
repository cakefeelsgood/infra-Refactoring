locals {
  prod_edge_origin_domain_name = var.prod_api_origin_domain_name != "" ? var.prod_api_origin_domain_name : var.prod_alb_dns_name
}
