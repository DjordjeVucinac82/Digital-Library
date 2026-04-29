package com.zuhlke.worker.config;

import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

// Active in the 'local' profile only — RabbitMQ is not used in AWS.
@Configuration
@Profile("local")
public class RabbitConfig {

    @Bean
    public Queue booksQueue() {
        return new Queue("books.compressed", true);
    }
}
