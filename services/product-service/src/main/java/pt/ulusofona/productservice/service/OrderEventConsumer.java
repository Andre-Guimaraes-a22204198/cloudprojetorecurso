package pt.ulusofona.productservice.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import pt.ulusofona.productservice.event.OrderCreatedEvent;
import pt.ulusofona.productservice.event.OrderItemEvent;
import pt.ulusofona.productservice.model.Product;
import pt.ulusofona.productservice.repository.ProductRepository;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.DeleteMessageRequest;
import software.amazon.awssdk.services.sqs.model.Message;
import software.amazon.awssdk.services.sqs.model.ReceiveMessageRequest;

import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class OrderEventConsumer {

    private final ProductRepository productRepository;
    private final SqsClient sqsClient;
    private final ObjectMapper objectMapper;

    @Value("${sqs.queue.url}")
    private String sqsQueueUrl;

    @Scheduled(fixedDelay = 5000)
    public void pollMessages() {
        try {
            ReceiveMessageRequest request = ReceiveMessageRequest.builder()
                    .queueUrl(sqsQueueUrl)
                    .maxNumberOfMessages(10)
                    .waitTimeSeconds(5)
                    .build();

            List<Message> messages = sqsClient.receiveMessage(request).messages();

            for (Message message : messages) {
                try {
                    OrderCreatedEvent event = objectMapper.readValue(
                            message.body(), OrderCreatedEvent.class);
                    handleOrderCreated(event);

                    sqsClient.deleteMessage(DeleteMessageRequest.builder()
                            .queueUrl(sqsQueueUrl)
                            .receiptHandle(message.receiptHandle())
                            .build());

                    log.info("Processed and deleted SQS message for order ID: {}", event.getOrderId());
                } catch (Exception e) {
                    log.error("Error processing SQS message: {}", message.body(), e);
                }
            }
        } catch (Exception e) {
            log.error("Error polling SQS queue", e);
        }
    }

    @Transactional
    public void handleOrderCreated(OrderCreatedEvent event) {
        log.info("Received OrderCreatedEvent for order ID: {}", event.getOrderId());
        try {
            for (OrderItemEvent item : event.getItems()) {
                Product product = productRepository.findById(item.getProductId())
                        .orElseThrow(() -> new RuntimeException(
                                "Product not found with ID: " + item.getProductId()));

                int newStock = product.getStockQuantity() - item.getQuantity();
                if (newStock < 0) {
                    log.warn("Insufficient stock for product {} (Order ID: {})",
                            product.getName(), event.getOrderId());
                    continue;
                }

                product.setStockQuantity(newStock);
                productRepository.save(product);
                log.info("Updated stock for product {}: {} -> {}",
                        product.getName(), product.getStockQuantity() + item.getQuantity(), newStock);
            }
        } catch (Exception e) {
            log.error("Error processing OrderCreatedEvent for order ID: {}", event.getOrderId(), e);
        }
    }
}