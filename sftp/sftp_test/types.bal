
type Person record {|
    string id;
    string firstName;
    string lastName;
    int age;
    string country;
|};

type Course record {|
    string id;
    string name;
    int credits;
|};

type Student record {
 string id;
    string fullName;
    string age;
    record {
        string title;
        int credits;
    }[] courses;
    int totalCredits;
    string visaType;
};

type SalesforceRutItem record {
    string Id;
    string Customer_Number__c;
    string ApArType__c;
    string GL_Account__c;
    record {
        string Invoice_Number__c;
    } Invoice__r;
    string TransTypeGL__c;
    string ApArNo__c;
    string Invoice__c;
    string VoucherType__c;
    string CompanyCode__c;
    string TransType__c;
    decimal Paid_Amount__c;
    string Dim1__c;
    string AR_Account__c;
    string Currency__c;
    boolean UBW_Status__c;
    string Status__c;
    string Rut_Application__c;
};
