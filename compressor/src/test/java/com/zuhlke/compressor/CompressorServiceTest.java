package com.zuhlke.compressor;

import com.zuhlke.compressor.service.CompressorService;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.mock.web.MockMultipartFile;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class CompressorServiceTest {

    @Test
    void shouldCompressAndPublishToQueue() {
        RabbitTemplate rabbitTemplate = mock(RabbitTemplate.class);
        CompressorService service = new CompressorService(rabbitTemplate);

        MockMultipartFile file = new MockMultipartFile(
                "file", "book.pdf", "application/pdf", "fake pdf content".getBytes()
        );

        service.compressAndPublish(file, "Clean Code");

        // Verify compressed bytes were published to the correct queue
        verify(rabbitTemplate, times(1))
                .convertAndSend(eq(CompressorService.QUEUE_NAME), any(byte[].class));
    }
}
