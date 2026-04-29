package com.zuhlke.compressor;

import com.zuhlke.compressor.service.CompressorService;
import com.zuhlke.compressor.service.MessagePublisher;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class CompressorServiceTest {

    @Test
    void shouldCompressAndPublishToQueue() {
        // Mock the MessagePublisher interface — works for both SQS and RabbitMQ publishers
        MessagePublisher publisher = mock(MessagePublisher.class);
        CompressorService service = new CompressorService(publisher);

        MockMultipartFile file = new MockMultipartFile(
                "file", "book.pdf", "application/pdf", "fake pdf content".getBytes()
        );

        service.compressAndPublish(file, "Clean Code");

        // Verify that the broker received compressed bytes
        verify(publisher, times(1)).publish(any(byte[].class));
    }
}
