package com.zuhlke.compressor.service;

// Abstracts the message broker so CompressorService doesn't depend on a specific broker.
// The 'aws' profile injects SqsMessagePublisher; 'local' injects RabbitMessagePublisher.
public interface MessagePublisher {

    void publish(byte[] data);
}
