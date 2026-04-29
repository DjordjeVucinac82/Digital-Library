package com.zuhlke.compressor.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.zip.GZIPOutputStream;

// Compresses uploaded PDFs and delegates publishing to the injected MessagePublisher.
// This class has no knowledge of the broker — it works with RabbitMQ locally
// and SQS in AWS without any code changes.
@Service
public class CompressorService {

    private static final Logger log = LoggerFactory.getLogger(CompressorService.class);

    private final MessagePublisher publisher;

    public CompressorService(MessagePublisher publisher) {
        this.publisher = publisher;
    }

    public void compressAndPublish(MultipartFile file, String title) {
        try {
            byte[] compressed = compress(file.getBytes());
            log.info("Compressed '{}': {} bytes → {} bytes", title, file.getSize(), compressed.length);
            publisher.publish(compressed);
            log.info("Published '{}' to message broker", title);
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
