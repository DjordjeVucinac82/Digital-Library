package com.zuhlke.compressor.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

// Active in the 'local' profile (docker-compose).
// Sends raw bytes directly to RabbitMQ — no Base64 needed (AMQP supports binary).
@Service
@Profile("local")
public class RabbitMessagePublisher implements MessagePublisher {

    private static final Logger log = LoggerFactory.getLogger(RabbitMessagePublisher.class);

    public static final String QUEUE_NAME = "books.compressed";

    private final RabbitTemplate rabbitTemplate;

    public RabbitMessagePublisher(RabbitTemplate rabbitTemplate) {
        this.rabbitTemplate = rabbitTemplate;
    }

    @Override
    public void publish(byte[] data) {
        rabbitTemplate.convertAndSend(QUEUE_NAME, data);
        log.info("Published {} bytes to RabbitMQ queue: {}", data.length, QUEUE_NAME);
    }
}
