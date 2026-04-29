package com.zuhlke.compressor.config;

import com.zuhlke.compressor.service.CompressorService;
import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

// Declares the queue so RabbitMQ creates it on startup if it doesn't exist.
// In AWS, this is replaced by an SQS queue created via Terraform.
@Configuration
public class RabbitConfig {

    @Bean
    public Queue booksQueue() {
        // durable=true so messages survive broker restarts
        return new Queue(CompressorService.QUEUE_NAME, true);
    }
}
