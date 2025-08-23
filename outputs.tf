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
  value = {
    main_app     = "http://${aws_instance.example.public_ip}:5000"
    ssh_access   = "ssh -i your-key.pem ec2-user@${aws_instance.example.public_ip}"
    app_logs     = "tail -f /opt/pgapp/app.log"
  }
}

output "setup_commands" {
  description = "Useful commands for managing your application"
  value = {
    check_status = "ssh -i your-key.pem ec2-user@${aws_instance.example.public_ip} 'systemctl status pgapp'"
    view_logs    = "ssh -i your-key.pem ec2-user@${aws_instance.example.public_ip} 'tail -f /opt/pgapp/app.log'"
    restart_app  = "ssh -i your-key.pem ec2-user@${aws_instance.example.public_ip} 'sudo systemctl restart pgapp'"
  }
}