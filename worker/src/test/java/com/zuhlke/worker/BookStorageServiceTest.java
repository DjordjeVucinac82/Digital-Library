package com.zuhlke.worker;

import com.zuhlke.worker.model.Book;
import com.zuhlke.worker.repository.BookRepository;
import com.zuhlke.worker.service.BookStorageService;
import org.junit.jupiter.api.Test;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class BookStorageServiceTest {

    @Test
    void shouldPersistCompressedBookToDatabase() {
        BookRepository repository = mock(BookRepository.class);
        when(repository.save(any(Book.class))).thenAnswer(i -> {
            Book b = i.getArgument(0);
            return b;
        });

        BookStorageService service = new BookStorageService(repository);
        byte[] fakeCompressedData = new byte[]{1, 2, 3, 4, 5};

        service.save(fakeCompressedData);

        verify(repository, times(1)).save(any(Book.class));
    }
}
