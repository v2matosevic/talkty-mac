import Foundation

/// Default vocabulary for coding/tech dictation. Two layers, ported 1:1:
/// 1. `promptContext` / `codingTerms` bias Whisper's decoder via initial_prompt
/// 2. `defaultReplacements` deterministically fix acoustically ambiguous words after transcription
public enum DefaultVocabulary {

    /// Contextual prompt for Whisper's initial_prompt. Natural sentences decode better
    /// than a word list. Keep under ~200 tokens.
    public static let promptContext =
        "Claude is an AI assistant by Anthropic. " +
        "I'm coding with React, Vue, Next.js, TypeScript, and Node.js. " +
        "Using kubectl for Kubernetes, Docker, Terraform, and nginx. " +
        "The backend uses PostgreSQL, Redis, GraphQL, FastAPI, and Express. " +
        "Deploying to AWS, Vercel, and Cloudflare with CI/CD via GitHub Actions. " +
        "Tools include VS Code, ESLint, Prettier, Jest, and Playwright."

    /// Post-transcription replacements. Key = what Whisper produces (case-insensitive),
    /// Value = correct replacement. Applied deterministically.
    public static let defaultReplacements: [String: String] = [
        // AI & LLM
        "cloud": "Claude", "claud": "Claude", "claw'd": "Claude", "claude ai": "Claude AI",
        "anthropik": "Anthropic", "chat gpt": "ChatGPT", "chatgbt": "ChatGPT",
        "open ai": "OpenAI", "olama": "Ollama", "o llama": "Ollama", "lang chain": "LangChain",
        // Frameworks & tools
        "cube cuddle": "kubectl", "cube CTL": "kubectl", "cube control": "kubectl", "kube CTL": "kubectl",
        "post gress": "PostgreSQL", "post gres": "PostgreSQL", "postgres QL": "PostgreSQL", "post gray SQL": "PostgreSQL",
        "mongo db": "MongoDB", "redis": "Redis", "express js": "Express.js", "next js": "Next.js",
        "node js": "Node.js", "vue js": "Vue.js", "fast api": "FastAPI", "graph QL": "GraphQL",
        "web socket": "WebSocket", "type script": "TypeScript", "java script": "JavaScript",
        // DevOps
        "docker file": "Dockerfile", "engine X": "nginx", "engine ex": "nginx", "terraform": "Terraform",
        "kubernetes": "Kubernetes", "github": "GitHub", "git lab": "GitLab", "VS code": "VS Code",
        // Acronyms
        "eye dee ee": "IDE", "see eye dee": "CI/CD", "jay son": "JSON", "ya ml": "YAML",
        "gee RPC": "gRPC", "sequel": "SQL",
    ]

    /// Curated coding/tech terms for the vocabulary prompt (and user-editable in settings).
    public static let codingTerms: [String] = [
        // AI & LLM
        "Claude", "Anthropic", "OpenAI", "GPT", "LLM", "Ollama", "Whisper",
        "Copilot", "ChatGPT", "Gemini", "LangChain", "RAG", "embeddings",
        // Frontend
        "React", "Vue", "Angular", "Svelte", "Next.js", "Nuxt", "Astro",
        "Tailwind", "Bootstrap", "Storybook", "Vite", "webpack",
        "useState", "useEffect", "querySelector", "JSX", "TSX",
        // Backend
        "Express", "NestJS", "FastAPI", "Django", "Flask", "Spring Boot",
        "ASP.NET", "middleware", "REST API", "GraphQL", "gRPC", "WebSocket", "OAuth", "JWT",
        // Languages & runtimes
        "TypeScript", "JavaScript", "Python", "Kotlin", "Rust", "Go",
        "Swift", "C#", ".NET", "Node.js", "Deno", "Bun",
        "async", "await", "boolean", "parseInt", "instanceof",
        // DevOps & infra
        "Docker", "Kubernetes", "kubectl", "Terraform", "Ansible",
        "nginx", "Apache", "CI/CD", "GitHub Actions", "GitLab", "Dockerfile", "Helm", "Istio",
        // Cloud
        "AWS", "Azure", "GCP", "Vercel", "Netlify", "Cloudflare", "Supabase", "Firebase", "Heroku",
        // Databases
        "PostgreSQL", "MongoDB", "Redis", "Elasticsearch", "SQLite", "MySQL", "Prisma", "Drizzle",
        "SQL", "NoSQL", "ORM", "CRUD",
        // Messaging
        "RabbitMQ", "Kafka", "Protocol Buffers",
        // Tools & editors
        "VS Code", "IntelliJ", "Neovim", "Figma", "GitHub", "npm", "yarn", "pnpm", "pip", "cargo", "NuGet",
        "ESLint", "Prettier", "Playwright", "Cypress", "Jest", "Vitest",
        // Formats & protocols
        "JSON", "YAML", "TOML", "regex", "HTTP", "HTTPS", "SSH",
        "API endpoint", "localhost", "WebAssembly", "WASM",
        // Concepts & acronyms
        "CLI", "SDK", "IDE", "API", "MVVM", "WPF", "XAML", "ARM", "x64", "x86", "CUDA", "Metal",
        // OS & platforms
        "Ubuntu", "Debian", "Arch", "Fedora", "macOS", "Windows", "Linux", "Homebrew",
    ]
}
