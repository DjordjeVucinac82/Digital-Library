package com.zuhlke.compressor.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.zip.GZIPOutputStream;

@Service
public class CompressorService {

    private static final Logger log = LoggerFactory.getLogger(CompressorService.class);

    // Queue name — in AWS this maps to an SQS queue URL via environment variable
    public static final String QUEUE_NAME = "books.compressed";

    private final RabbitTemplate rabbitTemplate;

    public CompressorService(RabbitTemplate rabbitTemplate) {
        this.rabbitTemplate = rabbitTemplate;
    }

    public void compressAndPublish(MultipartFile file, String title) {
        try {
            byte[] compressed = compress(file.getBytes());
            log.info("Compressed '{}': {} bytes → {} bytes", title, file.getSize(), compressed.length);

            // Publish compressed bytes to the broker; Worker consumes from the same queue
            rabbitTemplate.convertAndSend(QUEUE_NAME, compressed);
            log.info("Published '{}' to queue '{}'", title, QUEUE_NAME);

        } catch (IOException e) {
            throw new RuntimeException("Failed to compress or publish book: " + title, e);
        }
    }

    private byte[] compress(byte[] data) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (GZIPOutputStream gzip = new GZIPOutputStream(buffer)) {
            gzip.write(data);
        }
        return buffer.toByteArray();
    }
}
