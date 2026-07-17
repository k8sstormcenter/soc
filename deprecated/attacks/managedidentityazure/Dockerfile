# Use an official Node.js runtime as the base image
FROM node:16-alpine

# Set the working directory in the container to /app
WORKDIR /app

# Copy package.json and package-lock.json to the working directory
COPY package*.json ./

# Install the application dependencies
RUN npm install

# Copy the rest of the application code to the working directory
COPY . .

# Expose port 8080 for the application
EXPOSE 8080

# Start the application
CMD [ "node", "src/server.js" ]