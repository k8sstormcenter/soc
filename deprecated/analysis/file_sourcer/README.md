# Pixie FileSource Setup for Tetragon Logs

This folder contains scripts to simulate Tetragon logs and load them into Pixie using FileSource.

## ♻️ How to Use

1. **Initialize FileSource**

   Run the following to create the `tetragon.json` file in Minikube and attach it to Pixie:

   ```bash
   bash init_tetragon.sh
   ```

2. **Ingest New Logs**

   Whenever you want to simulate new log data:

   ```bash
   bash preprocess_tetragon.sh
   ```

   This updates the file so Pixie can ingest the new data.

3. **View Logs in Pixie**

   You can run the display script directly using:

   ```bash
   px run -f display_tetragon.pxl
   ```

---

### Files

* `tetragon.log`: Sample raw logs
* `example_tetragon_schema.json`: Schema example for reference
* `tetragon.json`: Final processed file that Pixie reads
* `init_tetragon.sh`: Setup script for first-time use
* `display_tetragon.pxl`: Script to visualize the data
* `ingest_tetragon.pxl`: Used by Pixie to connect the FileSource
* `delete_filesource.pxl`: (Optional) Use this to remove the FileSource if needed
