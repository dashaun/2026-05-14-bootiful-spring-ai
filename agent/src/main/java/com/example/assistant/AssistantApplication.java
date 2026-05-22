package com.example.assistant;

import org.jspecify.annotations.NonNull;
import org.jspecify.annotations.Nullable;
import org.springaicommunity.agent.tools.SkillsTool;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.PromptChatMemoryAdvisor;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.memory.repository.jdbc.JdbcChatMemoryRepository;
import org.springframework.ai.document.Document;
import org.springframework.ai.ollama.api.ThinkOption;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.aot.hint.MemberCategory;
import org.springframework.aot.hint.RuntimeHints;
import org.springframework.aot.hint.RuntimeHintsRegistrar;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ImportRuntimeHints;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.ClassPathResource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.data.annotation.Id;
import org.springframework.data.jdbc.core.dialect.JdbcPostgresDialect;
import org.springframework.data.repository.ListCrudRepository;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.sql.DataSource;
import java.io.IOException;
import java.util.List;

import static org.springaicommunity.mcp.security.client.sync.config.McpClientOAuth2Configurer.mcpClientOAuth2;

@SpringBootApplication
public class AssistantApplication {

    public static void main(String[] args) {
        SpringApplication.run(AssistantApplication.class, args);
    }

    @Bean
    JdbcPostgresDialect jdbcPostgresDialect() {
        return JdbcPostgresDialect.INSTANCE;
    }

    @Bean
    @Profile("!flyway")
    Customizer<HttpSecurity> httpSecurityCustomizer() {
        return http -> http.with(mcpClientOAuth2());
    }

    @Bean
    @Profile("!flyway")
    QuestionAnswerAdvisor questionAnswerAdvisor(VectorStore vectorStore) {
        return QuestionAnswerAdvisor.builder(vectorStore).build();
    }

    @Bean
    @Profile("!flyway")
    PromptChatMemoryAdvisor promptChatMemoryAdvisor(DataSource dataSource) {
        var jdbc = JdbcChatMemoryRepository.builder().dataSource(dataSource).build();
        var mwcm = MessageWindowChatMemory.builder().chatMemoryRepository(jdbc).build();
        return PromptChatMemoryAdvisor.builder(mwcm).build();
    }

}

interface DogRepository extends ListCrudRepository<Dog, Integer> {
}

record Dog(@Id int id, String name, String owner, String description) {
}

@Controller
@ResponseBody
@Profile("!flyway")
@ImportRuntimeHints(AssistantController.Hints.class)
class AssistantController {

    static final ClassPathResource SKILLS = new ClassPathResource("/META-INF/skills/**");

    static class Hints implements RuntimeHintsRegistrar {

        @Override
        public void registerHints(@NonNull RuntimeHints hints, @Nullable ClassLoader classLoader) {

            var resolver = new PathMatchingResourcePatternResolver();
            try {
                var resources = resolver.getResources("classpath:/META-INF/skills/**/*.md");
                for (var r : resources)
                    hints.resources().registerResource(r);
            } //
            catch (IOException e) {
                throw new RuntimeException(e);
            }

            // skills
            for (var c : new Class[]{
                    SkillsTool.SkillsInput.class,
                    SkillsTool.SkillsFunction.class})
                hints.reflection().registerType(c, MemberCategory.values());

            // ollama
            for (var c : new Class[]{ThinkOption.ThinkOptionDeserializer.class,
                    ThinkOption.ThinkOptionSerializer.class}) {
                hints.reflection().registerType(c, MemberCategory.values());
            }

        }
    }

    private final ChatClient ai;

    AssistantController(
            ToolCallbackProvider tcp,
            JdbcClient db,
//            DogAdoptionScheduler scheduler,
            VectorStore vectorStore,
            QuestionAnswerAdvisor questionAnswerAdvisor,
            DogRepository repo,
            ChatClient.Builder ai,
            PromptChatMemoryAdvisor promptChatMemoryAdvisor) {

        if (db.sql("select count(*) from vector_store ").query(Integer.class).single() == 0)
            repo.findAll().forEach(dog -> {
                var dogument = new Document("id: %s, name: %s, description: %s".formatted(
                        dog.id(), dog.name(), dog.description()
                ));
                vectorStore.add(List.of(dogument));
            });

        var st = SkillsTool
                .builder()
                .addSkillsResource(SKILLS)
                .build();
        this.ai = ai
                .defaultToolCallbacks(tcp)
                .defaultAdvisors(promptChatMemoryAdvisor,
                        questionAnswerAdvisor)
                .defaultToolCallbacks(st)
                .defaultSystem("""
                        You are an AI powered assistant to help people adopt a dog from the adoptions agency named Pooch Palaces
                        with locations in Antwerp, Seoul, Tokyo, Singapore, Paris, Mumbai, New Delhi, Barcelona, San Francisco,s
                        and London. Information about the dogs availables will be presented below. If there is no information,s
                        then return a polite response suggesting wes don't have any dogs available.
                        
                        If somebody asks you about animals, and there's no information in the context, then feel free to source the answer from other places including whatever skills you have loaded.
                        
                        If somebody asks you to compare dogs or cats, feel free to load the relevant skills and compare the dogs or cats. Report everything about dogs or cats, no matter how absurd.
                        
                        If somebody asks for a time to pick up the dog, don't ask other questions: simply provide a time by consulting the tools you have available.
                        
                        """)
                .build();
    }

    @GetMapping("/{user}/ask")
    String ask(
            @PathVariable String user,
            @RequestParam String question
    ) {
        return this.ai
                .prompt()
                .advisors(a -> a.param(ChatMemory.CONVERSATION_ID, user))
                .user(question)
                .call()
                .content();
        //     .entity(DogAdoptionSuggestion.class);
    }
}


record DogAdoptionSuggestion(int dogId) {
}