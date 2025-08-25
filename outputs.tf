output "instance_id" {
  description = "The instance ID of the PG Application server"
  value       = aws_instance.example.id
}

output "instance_public_ip" {
  description = "The public IP of the PG Application server"
  value       = aws_instance.example.public_ip
}

output "instance_public_dns" {
  description = "The public DNS of the PG Application server"
  value       = aws_instance.example.public_dns
}

output "application_urls" {
  description = "URLs to access your application"
  value       = "http://${aws_instance.example.public_ip}:5000"
}

output "ssh_connection" {
  description = "SSH connection command"
  value       = "ssh -i pg-app-key.pem ubuntu@${aws_instance.example.public_ip}"
}

output "deployment_commands" {
  description = "Useful commands for managing your Docker application"
  value = {
    check_docker_status = "ssh -i pg-app-key.pem ubuntu@${aws_instance.example.public_ip} 'docker ps'"
    check_app_logs     = "ssh -i pg-app-key.pem ubuntu@${aws_instance.example.public_ip} 'docker logs pgapp'"
    restart_app        = "ssh -i pg-app-key.pem ubuntu@${aws_instance.example.public_ip} 'cd /opt/pgapp && docker-compose restart'"
    redeploy_app       = "ssh -i pg-app-key.pem ubuntu@${aws_instance.example.public_ip} '/opt/pgapp/deploy.sh'"
    health_check       = "ssh -i pg-app-key.pem ubuntu@${aws_instance.example.public_ip} '/opt/pgapp/health-check.sh'"
  }
}

output "manual_deployment_info" {
  description = "Information for manual deployment"
  value = {
    deployment_script = "/opt/pgapp/deploy.sh"
    docker_compose_file = "/opt/pgapp/docker-compose.yml"
    service_name = "pgapp-docker"
    container_name = "pgapp"
  }
}