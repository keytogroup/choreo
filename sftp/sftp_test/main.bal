import ballerina/ftp;
import ballerina/http;
import ballerina/mime;

// Define configurable variables for SFTP connection
configurable string sftp_host = "127.0.0.1";
configurable int sftp_port = 2022;
configurable string sftp_username = "slask";
configurable string sftp_password = "slask";
configurable string sftp_upload_path = "/";
configurable string sftp_private_key_path = "./certs/private.key";
configurable string sftp_private_key_password = "keyPass123";

service /sftpService on new http:Listener(8080) {

    resource function post uploadFile(http:Caller caller, http:Request req) returns error? {
        // Create the SFTP client configuration with configurable properties
        ftp:ClientConfiguration sftpConfig = {
            protocol: ftp:SFTP,
            host: sftp_host,
            port: sftp_port,
            auth: {
                credentials: {
                    username: sftp_username,
                    password: sftp_password
                },
                privateKey: {
                    path: sftp_private_key_path,
                    password: sftp_private_key_password
                }
            }
        };

        // Create an SFTP client with the configuration
        ftp:Client sftpClient = check new (sftpConfig);

        // Check if the request is multipart
        if (req.hasHeader(mime:CONTENT_TYPE) && req.getContentType().startsWith(mime:MULTIPART_FORM_DATA)) {
            // Extract the multipart data from the request
            mime:Entity[] bodyParts = check req.getBodyParts();
            
            // Process each part (we're looking for the file)
            foreach mime:Entity part in bodyParts {
                // Check if this part is a file
                if (part.getContentDisposition().name == "file") {
                    // Get the file name from the Content-Disposition header or use default
                    string fileName = "uploaded_file.txt"; // Default filename if none provided
                    var contentDisposition = part.getContentDisposition();
                    if (contentDisposition.disposition != "") {
                        // Try to extract filename from headers or parameters if available
                        var params = contentDisposition.parameters;
                        if (params.hasKey("filename")) {
                            fileName = params.get("filename");
                        }
                    }
                    
                    // Get the file content as a byte stream
                    byte[] fileContent = check part.getByteArray();
                    
                    // Upload the file to SFTP server
                    string targetPath = sftp_upload_path + "/" + fileName;
                    check sftpClient->put(targetPath, fileContent);
                    
                    // Respond to the caller
                    check caller->respond("File '" + fileName + "' uploaded successfully to SFTP server.");
                    return;
                }
            }
            
            // If we get here, no file part was found
            check caller->respond({status: http:STATUS_BAD_REQUEST, body: "No file found in the request."});
            return;
        } else {
            // Not a multipart request, try to handle as a binary file upload
            byte[] fileContent = check req.getBinaryPayload();
            
            // Use a default filename or extract from headers if available
            string uploadFileName = "uploaded_file.bin";
            if (req.hasHeader("X-File-Name")) {
                string|http:HeaderNotFoundError headerValue = req.getHeader("X-File-Name");
                if (headerValue is string) {
                    uploadFileName = headerValue;
                }
            }
            
            // Upload the content to SFTP server
            string targetPath = sftp_upload_path + "/" + uploadFileName;
            check sftpClient->put(targetPath, fileContent);
            
            // Respond to the caller
            check caller->respond("File '" + uploadFileName + "' uploaded successfully to SFTP server.");
        }
    }
}
