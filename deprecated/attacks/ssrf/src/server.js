"use strict";

import axios from "axios";
import path from "path";
import express from "express";
import session from "express-session";
import { fileURLToPath } from "url";
import fs from "node:fs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Define default headers for all requests
axios.defaults.headers.common = {
  Accept: "text/plain,application/json,*/*",
  "Accept-Language": "en-US,en",
  "Accept-Encoding": "gzip, deflate, br",
  Connection: "keep-alive",
  "Upgrade-Insecure-Requests": "1",
  "Metadata-Flavor": "Google",
  Pragma: "no-cache",
  "Cache-Control": "no-cache",
};

const app = express();
const port = 8080;

// Initialize URL encoded request body parser.
app.use(express.urlencoded({ extended: false }));
app.use(express.text());

let sessionSecret;

if (process.env.NODE_ENV === "development") {
  // Use a hardcoded session secret in development
  sessionSecret = "secret";
} else {
  if (!process.env.PROJECT_ID || !process.env.SESSION_SECRET_NAME) {
    throw new Error(
      "PROJECT_ID and SESSION_SECRET_NAME environment variables are required when running in production."
    );
  }

  // Fetch session secret from Secret Manager in production
  const token_response = await axios.get(
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
  );
  const token = token_response.data.access_token;

  const secret_response = await axios.get(
    `https://secretmanager.googleapis.com/v1/projects/${process.env.PROJECT_ID}/secrets/${process.env.SESSION_SECRET_NAME}/versions/latest:access`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    }
  );
  sessionSecret = Buffer.from(
    secret_response.data.payload.data,
    "base64"
  ).toString();
}

// Initialize session middleware.
app.use(
  session({
    resave: false,
    saveUninitialized: true,
    secret: sessionSecret,
  })
);

// Local in-memory user database
const users = {
  foo: {
    password: "bar",
    username: "foo",
    fullname: "Foo Bar",
    email: "foobar@example.com",
    about:
      "Fugiat ipsum ipsum deserunt culpa aute sint do nostrud anim incididunt cillum culpa consequat. Excepteur qui ipsum aliquip consequat sint. Sit id mollit nulla mollit nostrud in ea officia proident. Irure nostrud pariatur mollit ad adipisicing reprehenderit deserunt qui eu.",
    picture: `data:image/jpeg;base64,${fs
      .readFileSync(
        path.join(__dirname, "resources", "default-profile-picture.jpg")
      )
      .toString("base64")}`,
  },
};

/**
 * Returns the authenticated user if the provided credentials are valid, otherwise returns null.
 */
function authenticate(username, password) {
  var user = users[username];

  if (user && user.password === password) {
    return user;
  }

  return null;
}

/**
 * Middleware that restricts access to authenticated users only.
 * Redirects to /login if the user is not authenticated. Intended for web page paths.
 */
function restrict(req, res, next) {
  if (req.session.username) {
    next();
  } else {
    res.redirect("/login");
  }
}

/**
 * Middleware that restricts access to authenticated users only.
 * Sends a 403 status code if the user is not authenticated. Intended for API paths.
 */
function apiRestrict(req, res, next) {
  if (req.session.username) {
    next();
  } else {
    res.status(403).send("Access denied");
  }
}

// Root path redirects to /login.
app.get("/", function (req, res) {
  res.redirect("/login");
});

// Serves the login page.
app.get("/login", function (req, res) {
  res.sendFile(path.join(__dirname, "views", "login.html"));
});

// Serves the profile page of the authenticated user.
app.get("/profile", restrict, function (req, res) {
  res.sendFile(path.join(__dirname, "views", "profile.html"));
});

// Defines router for the API endpoints.
const api = express.Router();
app.use("/api", api);

// Authenticates the user and redirects to the profile page if successful.
api.post("/login", (req, res) => {
  const user = authenticate(req.body.username, req.body.password);

  if (user) {
    req.session.username = user.username;
    res.redirect("/profile");
  } else {
    res.redirect("/login");
  }
});

// Returns the profile of the authenticated user.
api.get("/profile", apiRestrict, (req, res) => {
  const user = users[req.session.username];
  const { password, ...userWithoutPassword } = user;
  res.json(userWithoutPassword);
});

// Updates the profile of the authenticated user by uploading an image.
api.post("/profile/upload-picture", apiRestrict, async (req, res) => {
  const image = req.body;

  if (!image) {
    return res.status(400).send("Missing image data");
  }

  // Update the profile picture of the authenticated user
  const user = users[req.session.username];
  user.picture = image;

  // Respond with the updated profile picture
  res.send(image);
});

// Updates the profile of the authenticated user by providing a URL pointing to an image.
api.patch("/profile/change-picture", apiRestrict, async (req, res) => {
  if (!req.query.url) {
    return res.status(400).send("Missing URL parameter");
  }

  let image;

  try {
    // If image is provided as URL, request it
    const url = new URL(req.query.url);
    const response = await axios.get(url, {
      responseType: "arraybuffer",
    });

    // Use the content type to infer the image type and generate a data URL containing the base64-encoded image
    const contentType = response.headers["content-type"];
    const imageBuffer = response.data;
    image = `data:${contentType};base64,${imageBuffer.toString("base64")}`;
  } catch (error) {
    console.error(error);
    return res.status(400).send("Failed to download image");
  }

  // Update the profile picture of the authenticated user
  const user = users[req.session.username];
  user.picture = image;

  // Respond with the updated profile picture
  res.send(image);
});

app.listen(port, () => {
  console.log(`Server listening on port ${port}`);
});
