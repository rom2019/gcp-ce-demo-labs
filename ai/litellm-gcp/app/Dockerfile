FROM ghcr.io/berriai/litellm:main-latest

# LiteLLM 설정 파일 복사
COPY config.yaml /app/config.yaml

EXPOSE 4000

# Cloud Run은 PORT 환경변수를 자동 주입하지만
# LiteLLM은 --port 인수로 명시하는 게 안전
ENTRYPOINT ["litellm"]
CMD ["--config", "/app/config.yaml", "--port", "4000", "--num_workers", "4"]
