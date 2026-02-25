# pre-build stage
FROM node:23-alpine as node

FROM ruby:3.4.4-alpine3.21 AS pre-builder

ARG PNPM_VERSION="10.2.0"
ENV PNPM_VERSION=${PNPM_VERSION}

# install node
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node /usr/local/include/node /usr/local/include/node
RUN ln -s /usr/local/bin/node /usr/local/bin/nodejs \
  && ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Install system dependencies
RUN apk update && apk add --no-cache \
  build-base \
  git \
  tzdata \
  postgresql-dev \
  postgresql-client \
  curl \
  xz \
  vips-dev \
  imagemagick \
  libffi-dev \
  shared-mime-info

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm@${PNPM_VERSION}

# Copy dependency files first for caching
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local force_ruby_platform true \
  && bundle config set --local without 'development test' \
  && bundle install -j "$(getconf _NPROCESSORS_ONLN)" -r 3

COPY package.json pnpm-lock.yaml ./
RUN pnpm config set store-dir /pnpm/store \
  && pnpm i --frozen-lockfile

# Copy application code
COPY . .

# Generate production assets
RUN SECRET_KEY_BASE=precompile_placeholder RAILS_LOG_TO_STDOUT=enabled bundle exec rake assets:precompile \
  && rm -rf spec node_modules tmp/cache

# Generate .git_sha file
RUN git rev-parse HEAD > /app/.git_sha

# final build stage
FROM ruby:3.4.4-alpine3.21

ARG PNPM_VERSION="10.2.0"
ENV PNPM_VERSION=${PNPM_VERSION}

RUN apk update && apk add --no-cache \
  build-base \
  openssl \
  tzdata \
  postgresql-client \
  imagemagick \
  git \
  vips \
  ffmpeg \
  shared-mime-info

WORKDIR /app

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/bin/node /usr/local/bin/nodejs \
  && ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
  && npm install -g pnpm@${PNPM_VERSION}

COPY --from=pre-builder /usr/local/bundle /usr/local/bundle
COPY --from=pre-builder /app /app

ENV RAILS_ENV=production
ENV NODE_ENV=production
ENV RAILS_SERVE_STATIC_FILES=true
ENV RAILS_LOG_TO_STDOUT=true

EXPOSE 3000

CMD ["bundle", "exec", "rails", "s", "-b", "0.0.0.0"]
