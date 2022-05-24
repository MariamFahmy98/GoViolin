# Build Stage
FROM golang:1.17.3 AS Builder

WORKDIR /app

COPY go.mod go.sum ./

RUN go get -d -v ./...

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o GoViolin .

# Run Stage
FROM alpine:latest 

RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copying the binary of the application from the builder stage.
COPY --from=Builder /app/GoViolin .

# Copying the required static files.
COPY css/ ./css/
COPY img/ ./img/
COPY mp3/ ./mp3/
COPY templates/ ./templates/

ENV PORT=3000
ENTRYPOINT ["./GoViolin"] 