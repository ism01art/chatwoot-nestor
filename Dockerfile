FROM chatwoot/chatwoot:latest

ENV RAILS_ENV=production
ENV NODE_ENV=production

# Se você precisar instalar dependências extras, adicione aqui (opcional)
# RUN apt-get update && apt-get install -y <pacotes>

# Copia as variáveis de ambiente se quiser usar localmente (opcional)
# COPY .env .env

CMD ["/bin/bash", "-c", "bundle exec rails db:prepare && bundle exec rails s -b 0.0.0.0"]
