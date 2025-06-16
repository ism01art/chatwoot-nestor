# ---- Builder ----
FROM ruby:3.3.8-slim AS builder

# Variáveis de ambiente essenciais
ENV RAILS_ENV=production
ENV BUNDLE_WITHOUT=development:test
ENV BUNDLE_PATH=/gems
ENV BUNDLER_VERSION=2.5.16

# Instala libs essenciais para build de gems e Node/Yarn
RUN apt-get update && apt-get install -y \
  build-essential \
  libpq-dev \
  nodejs \
  yarn \
  git \
  imagemagick \
  libvips \
  curl \
  && gem install bundler -v "$BUNDLER_VERSION"

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install -j$(nproc) --retry 3

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Atualiza browserslist/caniuse-lite antes do build dos assets!
RUN npx browserslist@latest --update-db || true

COPY . .

# Pré-compila os assets Rails
RUN SECRET_KEY_BASE=dummy bundle exec rake assets:precompile

# ---- Final Image ----
FROM ruby:3.3.8-slim

ENV RAILS_ENV=production
ENV BUNDLE_WITHOUT=development:test
ENV BUNDLE_PATH=/gems
ENV BUNDLER_VERSION=2.5.16

# Só as libs de runtime necessárias!
RUN apt-get update && apt-get install -y \
  libpq5 \
  nodejs \
  yarn \
  imagemagick \
  libvips \
  curl \
  && gem install bundler -v "$BUNDLER_VERSION" \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copia gems instaladas, código app, e assets já prontos do builder
COPY --from=builder /gems /gems
COPY --from=builder /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
