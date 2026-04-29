package com.zuhlke.compressor.config;

import com.zuhlke.compressor.service.RabbitMessagePublisher;
import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

// Declares the RabbitMQ queue on startup — only active in the 'local' profile.
// In AWS (profile=aws), the queue is created via Terraform in infra/modules/sqs/.
@Configuration
@Profile("local")
public class RabbitConfig {

    @Bean
    public Queue booksQueue() {
        // durable=true so messages survive broker restarts
        return new Queue(RabbitMessagePublisher.QUEUE_NAME, true);
    }
}
