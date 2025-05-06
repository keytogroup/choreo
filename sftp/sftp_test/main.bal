import ballerina/ftp;
import ballerina/http;
import ballerina/log;
import ballerina/mime;
import ballerina/time;


listener http:Listener httpDefaultListener = http:getDefaultListener();

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
        log:printInfo("Received file upload request");

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

        log:printInfo("Connecting to SFTP server", host = sftp_host, port = sftp_port);

        // Create an SFTP client with the configuration
        ftp:Client sftpClient = check new (sftpConfig);
        log:printInfo("Successfully connected to SFTP server");

        // Check if the request is multipart
        if (req.hasHeader(mime:CONTENT_TYPE) && req.getContentType().startsWith(mime:MULTIPART_FORM_DATA)) {
            log:printInfo("Processing multipart form data request");
            // Extract the multipart data from the request
            mime:Entity[] bodyParts = check req.getBodyParts();
            log:printInfo("Found " + bodyParts.length().toString() + " parts in multipart request");

            // Process each part (we're looking for the file)
            foreach mime:Entity part in bodyParts {
                // Check if this part is a file
                if (part.getContentDisposition().name == "file") {
                    log:printInfo("Found file part in request");
                    // Get the file name from the Content-Disposition header or use default
                    string fileName = "uploaded_file.txt"; // Default filename if none provided
                    var contentDisposition = part.getContentDisposition();
                    if (contentDisposition.disposition != "") {
                        // Try to extract filename from headers or parameters if available
                        var params = contentDisposition.parameters;
                        if (params.hasKey("filename")) {
                            fileName = params.get("filename");
                            log:printInfo("Extracted filename from request", fileName = fileName);
                        } else {
                            log:printInfo("Using default filename", fileName = fileName);
                        }
                    }

                    // Get the file content as a byte stream
                    byte[] fileContent = check part.getByteArray();
                    log:printInfo("File content size", bytes = fileContent.length().toString());

                    // Upload the file to SFTP server
                    string targetPath = sftp_upload_path + "/" + fileName;
                    log:printInfo("Uploading file to SFTP server", path = targetPath);
                    check sftpClient->put(targetPath, fileContent);
                    log:printInfo("File upload completed successfully");

                    // Respond to the caller
                    check caller->respond("File '" + fileName + "' uploaded successfully to SFTP server.");
                    return;
                }
            }

            // If we get here, no file part was found
            log:printWarn("No file part found in multipart request");
            check caller->respond({status: http:STATUS_BAD_REQUEST, body: "No file found in the request."});
            return;
        } else {
            // Not a multipart request, try to handle as a text payload
            log:printInfo("Processing text payload request");
            string textContent = check req.getTextPayload();
            log:printInfo("Text content size", characters = textContent.length().toString());

            // Use a default filename or extract from headers if available
            string uploadFileName = "uploaded_file.txt";
            if (req.hasHeader("X-File-Name")) {
                string|http:HeaderNotFoundError headerValue = req.getHeader("X-File-Name");
                if (headerValue is string) {
                    uploadFileName = headerValue;
                    log:printInfo("Using filename from X-File-Name header", fileName = uploadFileName);
                }
            } else {
                log:printInfo("Using default filename for text upload", fileName = uploadFileName);
            }

            // Upload the content to SFTP server
            string targetPath = sftp_upload_path + "/" + uploadFileName;
            log:printInfo("Uploading text file to SFTP server", path = targetPath);
            check sftpClient->put(targetPath, textContent);
            log:printInfo("Text file upload completed successfully");

            // Respond to the caller
            check caller->respond("File '" + uploadFileName + "' uploaded successfully to SFTP server.");
        }
    }

    resource function get listfiles(http:Caller caller, http:Request req) returns error? {
        log:printInfo("Received request to list files");

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

        log:printInfo("Connecting to SFTP server for listing files", host = sftp_host, port = sftp_port);

        // Create an SFTP client with the configuration
        ftp:Client sftpClient = check new (sftpConfig);
        log:printInfo("Successfully connected to SFTP server");

        // Get the path from query parameter or use default upload path
        string path = sftp_upload_path;
        map<string[]> queryParams = req.getQueryParams();
        if (queryParams.hasKey("path")) {
            string[] pathValues = queryParams.get("path");
            if (pathValues.length() > 0) {
                path = pathValues[0];
                log:printInfo("Using path from query parameter", path = path);
            }
        }

        // List files in the directory
        log:printInfo("Listing files in directory", path = path);
        ftp:FileInfo[] fileList = check sftpClient->list(path);
        log:printInfo("Found " + fileList.length().toString() + " files/directories");

        // Convert file list to JSON
        json[] jsonFileList = [];
        foreach ftp:FileInfo fileInfo in fileList {
            json fileJson = {
                "name": fileInfo.name,
                "size": fileInfo.size,
                "path": path + "/" + fileInfo.name,
                "lastModifiedTimestamp": fileInfo.lastModifiedTimestamp,
                "isFolder": fileInfo.isFolder,
                "isFile": fileInfo.isFile,
                "extension": fileInfo.extension
            };
            jsonFileList.push(fileJson);
        }

        // Create response JSON
        json response = {
            "path": path,
            "fileCount": fileList.length(),
            "files": jsonFileList
        };

        // Send the response back
        check caller->respond(response);
    }

    function name() => ();
}

service /transform on new http:Listener(8801) {
    resource function get xmlmapper() returns error|xml|http:InternalServerError {
        do {
            return xml `<ml></ml>`;
        } on fail error err {
            log:printError("Error in XML transformation", err);
            return error("XML transformation error: " + err.message());
        }
        
    }
    resource function get jsontransform() returns error|json|http:InternalServerError {
        do {
            Student student = transform({
                                            id: "1001",
                                            firstName: "Daniel",
                                            lastName: "Hirvonen",
                                            age: 25,
                                            country: "SE"
                                        }, [
                                            {
                                                id: "CS6002",
                                                name: "Computation Structures",
                                                credits: 4
                                            },
                                            {
                                                id: "CS6002",
                                                name: "Computation Structures",
                                                credits: 4
                                            },
                                            {
                                                id: "CS6002",
                                                name: "Computation Structures",
                                                credits: 4
                                            },
                                            {
                                                id: "CS6002",
                                                name: "Computation Structures",
                                                credits: 42222222222222
                                            }
                                        ]);
            return student.toJson();

        } on fail error err {
            // handle error
            return error("unhandled error", err);
        }
    }

    // Format date to the required format for XML (YYYY-MM-DD)
    private function formatDate(time:Utc date) returns string {
        // Get current date in ISO format
        string currentDate = time:utcToString(date);
        // Extract just the date part (first 10 characters: YYYY-MM-DD)
        return currentDate.substring(0, 10);
    }

    // Generate RUT Invoice XML from SalesforceRutItem array
    private function generateRutInvoiceXML(SalesforceRutItem[] rutItems, string skvRef, string rutName) returns string|error {
        if rutItems.length() == 0 {
            return "No";
        }

        // Get current date and time
        time:Utc now = time:utcNow();
        string currentDateTime = time:utcToString(now);
        
        // Parse the ISO date string (format: 2025-05-05T15:36:07.123Z)
        string datePart = currentDateTime.substring(0, 10); // YYYY-MM-DD
        string timePart = currentDateTime.substring(11, 19); // HH:MM:SS
        
        // Extract components
        string year = datePart.substring(0, 4);
        string month = datePart.substring(5, 7);
        string day = datePart.substring(8, 10);
        string hour = timePart.substring(0, 2);
        string minute = timePart.substring(3, 5);
        string second = timePart.substring(6, 8);
        
        // Create period and batch ID
        string period = year + month;
        string batchId = period + day + hour + minute + second;


        string mainVal = "<agr:ABWTransaction xsi:schemaLocation=\"http://services.agresso.com/schema/ABWTransaction/2011/11/14 http://services.agresso.com/schema/ABWTransaction/2011/11/14/ABWTransaction.xsd\" xmlns:agrlib=\"http://services.agresso.com/schema/ABWSchemaLib/2011/11/14\" xmlns:agr=\"http://services.agresso.com/schema/ABWTransaction/2011/11/14\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">";
        mainVal = mainVal + "<agr:Interface>SF</agr:Interface>";
        mainVal = mainVal + string `<agrlib:BatchId>${batchId}</agrlib:BatchId>`;

        foreach SalesforceRutItem rut in rutItems {
            mainVal = mainVal + "<agr:Voucher>";
            mainVal = mainVal + string `<agrlib:VoucherType>${rut.VoucherType__c}</agrlib:VoucherType>`;
            mainVal = mainVal + string `<agrlib:CompanyCode>${rut.CompanyCode__c}</agrlib:CompanyCode>`;
            mainVal = mainVal + string `<agrlib:Period>${period}</agrlib:Period>`;
            mainVal = mainVal + string `<agr:VoucherDate>${self.formatDate(now)}</agr:VoucherDate>`;

            // First transaction (negative amount)
            mainVal = mainVal + "<agr:Transaction>";
            mainVal = mainVal + string `<agrlib:TransType>${rut.TransType__c}</agrlib:TransType>`;
            mainVal = mainVal + string `<agrlib:Description>${skvRef}</agrlib:Description>`;
            mainVal = mainVal + string `<agr:ExternalRef>${rutName}</agr:ExternalRef>`;
            mainVal = mainVal + "<agr:Amounts>";
            mainVal = mainVal + string `<agrlib:Amount>-${rut.Paid_Amount__c}</agrlib:Amount>`;
            mainVal = mainVal + string `<agrlib:CurrAmount>-${rut.Paid_Amount__c}</agrlib:CurrAmount>`;
            mainVal = mainVal + "</agr:Amounts>";
            mainVal = mainVal + "<agr:GLAnalysis>";
            mainVal = mainVal + string `<agrlib:Account>${rut.AR_Account__c}</agrlib:Account>`;
            mainVal = mainVal + string `<agr:Dim1>${rut.Dim1__c}</agr:Dim1>`;
            mainVal = mainVal + string `<agrlib:Currency>${rut.Currency__c}</agrlib:Currency>`;
            mainVal = mainVal + "</agr:GLAnalysis>";
            mainVal = mainVal + "<agr:ApArInfo>";
            mainVal = mainVal + string `<agrlib:ApArType>${rut.ApArType__c}</agrlib:ApArType>`;
            mainVal = mainVal + string `<agrlib:ApArNo>${rut.Customer_Number__c}</agrlib:ApArNo>`;
            mainVal = mainVal + string `<agrlib:InvoiceNo>${rut.Invoice__r.Invoice_Number__c}</agrlib:InvoiceNo>`;
            mainVal = mainVal + string `<agrlib:VoucherRef>${rut.Invoice__r.Invoice_Number__c}</agrlib:VoucherRef>`;
            mainVal = mainVal + "</agr:ApArInfo>";
            mainVal = mainVal + "</agr:Transaction>";

            // Second transaction (positive amount)
            mainVal = mainVal + "<agr:Transaction>";
            mainVal = mainVal + string `<agrlib:TransType>${rut.TransTypeGL__c}</agrlib:TransType>`;
            mainVal = mainVal + string `<agrlib:Description>${skvRef}</agrlib:Description>`;
            mainVal = mainVal + string `<agr:ExternalRef>${rutName}</agr:ExternalRef>`;
            mainVal = mainVal + "<agr:Amounts>";
            mainVal = mainVal + string `<agrlib:Amount>${rut.Paid_Amount__c}</agrlib:Amount>`;
            mainVal = mainVal + string `<agrlib:CurrAmount>${rut.Paid_Amount__c}</agrlib:CurrAmount>`;
            mainVal = mainVal + "</agr:Amounts>";
            mainVal = mainVal + "<agr:GLAnalysis>";
            mainVal = mainVal + string `<agrlib:Account>${rut.GL_Account__c}</agrlib:Account>`;
            mainVal = mainVal + string `<agr:Dim1>${rut.Dim1__c}</agr:Dim1>`;
            mainVal = mainVal + string `<agrlib:Currency>${rut.Currency__c}</agrlib:Currency>`;
            mainVal = mainVal + "</agr:GLAnalysis>";
            mainVal = mainVal + "<agr:ApArInfo>";
            mainVal = mainVal + string `<agrlib:ApArType>${rut.ApArType__c}</agrlib:ApArType>`;
            mainVal = mainVal + string `<agrlib:ApArNo>${rut.Customer_Number__c}</agrlib:ApArNo>`;
            mainVal = mainVal + string `<agrlib:InvoiceNo>${rut.Invoice__r.Invoice_Number__c}</agrlib:InvoiceNo>`;
            mainVal = mainVal + string `<agrlib:VoucherRef>${rut.Invoice__r.Invoice_Number__c}</agrlib:VoucherRef>`;
            mainVal = mainVal + "</agr:ApArInfo>";
            mainVal = mainVal + "</agr:Transaction>";
            mainVal = mainVal + "</agr:Voucher>";
        }

        mainVal = mainVal + "</agr:ABWTransaction>";
        
        // Replace null values and escape ampersands
        string cleanedXml = mainVal;
        // Use string:replace instead of string.replace
        cleanedXml = re`null`.replace(cleanedXml, "");
        cleanedXml = re`&`.replace(cleanedXml, "&amp;");

        // Validate the XML against the XSD schema
        Unit4XmlValidator validator = new();
        var validation = validator.validateXml(cleanedXml, "transaction");
        if (!validation.isValid) {
            string errorMsg = "Invalid XML generated";
            foreach string err in validation.errors {
                log:printError(errorMsg + ": " + err);
            }
            return error(errorMsg);
        }
        return cleanedXml;
    }

    // Convert JSON to SalesforceRutItem
    private function jsonToRutItem(map<json> jsonData) returns SalesforceRutItem|error {
        // Extract values with proper type conversion
        string id = jsonData.hasKey("Id") ? (jsonData.get("Id").toString()) : "";
        string customerNumber = jsonData.hasKey("Customer_Number__c") ? (jsonData.get("Customer_Number__c").toString()) : "";
        string apArType = jsonData.hasKey("ApArType__c") ? (jsonData.get("ApArType__c").toString()) : "";
        string glAccount = jsonData.hasKey("GL_Account__c") ? (jsonData.get("GL_Account__c").toString()) : "";
        
        // Handle nested record
        record {string Invoice_Number__c;} invoiceR = {Invoice_Number__c: ""};
        if jsonData.hasKey("Invoice__r") {
            json invoiceRJson = jsonData.get("Invoice__r");
            if invoiceRJson is map<json> && invoiceRJson.hasKey("Invoice_Number__c") {
                invoiceR.Invoice_Number__c = invoiceRJson.get("Invoice_Number__c").toString();
            }
        }
        
        string transTypeGL = jsonData.hasKey("TransTypeGL__c") ? (jsonData.get("TransTypeGL__c").toString()) : "";
        string apArNo = jsonData.hasKey("ApArNo__c") ? (jsonData.get("ApArNo__c").toString()) : "";
        string invoice = jsonData.hasKey("Invoice__c") ? (jsonData.get("Invoice__c").toString()) : "";
        string voucherType = jsonData.hasKey("VoucherType__c") ? (jsonData.get("VoucherType__c").toString()) : "";
        string companyCode = jsonData.hasKey("CompanyCode__c") ? (jsonData.get("CompanyCode__c").toString()) : "";
        string transType = jsonData.hasKey("TransType__c") ? (jsonData.get("TransType__c").toString()) : "";
        
        // Convert numeric value
        decimal paidAmount = 0;
        if jsonData.hasKey("Paid_Amount__c") {
            json paidAmountJson = jsonData.get("Paid_Amount__c");
            if paidAmountJson is float || paidAmountJson is int {
                paidAmount = <decimal>paidAmountJson;
            } else if paidAmountJson is string {
                var decimalValue = decimal:fromString(paidAmountJson.toString());
                if decimalValue is decimal {
                    paidAmount = decimalValue;
                }
            }
        }
        
        string dim1 = jsonData.hasKey("Dim1__c") ? (jsonData.get("Dim1__c").toString()) : "";
        string arAccount = jsonData.hasKey("AR_Account__c") ? (jsonData.get("AR_Account__c").toString()) : "";
        string currency = jsonData.hasKey("Currency__c") ? (jsonData.get("Currency__c").toString()) : "";
        
        // Convert boolean value
        boolean ubwStatus = false;
        if jsonData.hasKey("UBW_Status__c") {
            json ubwStatusJson = jsonData.get("UBW_Status__c");
            if ubwStatusJson is boolean {
                ubwStatus = ubwStatusJson;
            } else if ubwStatusJson is string {
                ubwStatus = ubwStatusJson.toString().toLowerAscii() == "true";
            }
        }
        
        string status = jsonData.hasKey("Status__c") ? (jsonData.get("Status__c").toString()) : "";
        string rutApplication = jsonData.hasKey("Rut_Application__c") ? (jsonData.get("Rut_Application__c").toString()) : "";
        
        // Create and return the SalesforceRutItem
        return {
            Id: id,
            Customer_Number__c: customerNumber,
            ApArType__c: apArType,
            GL_Account__c: glAccount,
            Invoice__r: invoiceR,
            TransTypeGL__c: transTypeGL,
            ApArNo__c: apArNo,
            Invoice__c: invoice,
            VoucherType__c: voucherType,
            CompanyCode__c: companyCode,
            TransType__c: transType,
            Paid_Amount__c: paidAmount,
            Dim1__c: dim1,
            AR_Account__c: arAccount,
            Currency__c: currency,
            UBW_Status__c: ubwStatus,
            Status__c: status,
            Rut_Application__c: rutApplication
        };
    }
    
    // Sample data for SalesforceRutItem
    private function getSampleRutItem() returns SalesforceRutItem {
        return {
            Id: "SF123456",
            Customer_Number__c: "CUST001",
            ApArType__c: "AR",
            GL_Account__c: "1200",
            Invoice__r: {
                Invoice_Number__c: "INV-2023-001"
            },
            TransTypeGL__c: "GL",
            ApArNo__c: "CUST001",
            Invoice__c: "INV-2023-001",
            VoucherType__c: "IV",
            CompanyCode__c: "1000",
            TransType__c: "AR",
            Paid_Amount__c: 1500.50,
            Dim1__c: "DEPT100",
            AR_Account__c: "1100",
            Currency__c: "USD",
            UBW_Status__c: false,
            Status__c: "Pending",
            Rut_Application__c: "RUT-APP-001"
        };
    }

    // POST endpoint for XML transformation
    resource function post xmltransform(@http:Payload json payload) returns error|xml|http:Response {
        do {
            // Convert JSON payload to SalesforceRutItem or use sample data
            SalesforceRutItem[] rutItems;
            
            // Check if payload is an array
            if payload is json[] {
                // Convert each item individually to handle potential errors better
                rutItems = [];
                foreach json item in payload {
                    if item is map<json> {
                        do {
                            // Manual conversion from JSON to SalesforceRutItem
                            SalesforceRutItem rutItem = check self.jsonToRutItem(item);
                            rutItems.push(rutItem);
                        } on fail error err {
                            log:printWarn("Error converting JSON to SalesforceRutItem: " + err.message());
                            // Use sample data for this item
                            rutItems.push(self.getSampleRutItem());
                        }
                    }
                }
                
                // If no valid items were found, use sample data
                if rutItems.length() == 0 {
                    log:printWarn("No valid items in payload, using sample data");
                    rutItems = [self.getSampleRutItem()];
                }
            } else if payload is map<json> {
                // Single item, convert to array
                do {
                    // Manual conversion from JSON to SalesforceRutItem
                    SalesforceRutItem rutItem = check self.jsonToRutItem(payload);
                    rutItems = [rutItem];
                } on fail error err {
                    log:printWarn("Error converting JSON to SalesforceRutItem: " + err.message());
                    // Use sample data
                    rutItems = [self.getSampleRutItem()];
                }
            } else {
                // Use sample data if payload is not valid
                log:printWarn("Invalid payload format, using sample data");
                rutItems = [self.getSampleRutItem()];
            }
            
            // Generate XML
            string xmlString = check self.generateRutInvoiceXML(
                rutItems, 
                "SKV-REF-001", 
                "RUT-NAME-001"
            );
            
            // Convert to XML and return
            xml xmlOutput = check xml:fromString(xmlString);
            
            // Create response with XML content type
            http:Response response = new;
            response.setXmlPayload(xmlOutput);
            response.setHeader("Content-Type", "application/xml");
            return response;
        } on fail error err {
            log:printError("Error in XML transformation", err);
            return error("XML transformation error: " + err.message());
        }
    }
    
    // GET endpoint for XML transformation with sample data
    resource function get xmltransform() returns error|xml|http:Response {
        do {
            // Use sample data
            SalesforceRutItem[] rutItems = [self.getSampleRutItem()];
            
            // Generate XML
            string xmlString = check self.generateRutInvoiceXML(
                rutItems, 
                "SKV-REF-001", 
                "RUT-NAME-001"
            );
            
            // Convert to XML and return
            xml xmlOutput = check xml:fromString(xmlString);
            
            // Create response with XML content type
            http:Response response = new;
            response.setXmlPayload(xmlOutput);
            response.setHeader("Content-Type", "application/xml");
            return response;
        } on fail error err {
            log:printError("Error in XML transformation", err);
            return error("XML transformation error: " + err.message());
        }
    }
}
