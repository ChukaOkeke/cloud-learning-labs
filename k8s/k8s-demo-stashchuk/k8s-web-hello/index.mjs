import express from "express";
import os from "os";

const app = express();
const PORT = 3000;

app.get("/", (req, res) => {
  const hello_message = `VERSION 2: Hello from the ${os.hostname()}!`;
  console.log(hello_message);
  res.send(hello_message);
});

app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
