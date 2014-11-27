#ifndef PARSER_H
#define PARSER_H

#include <boost/filesystem.hpp>   
#include <map>

#include "types.h"
#include "Tokenizer.h"
#include "info.h"

using namespace std;

enum class XmlTokenType {OPEN, CLOSE, TEXT, IGNORE };

class XmlElement {
public:
    XmlElement(string& tagName)
        {
            _tagName = tagName;
            _text = "";
        }
    
    void addChild(XmlElement* child);
    void addAttr(string& xml);
    void addText(string& text);
    
    string text();
    void printXmlTree(size_t depth);

    XmlElement* firstNodebyName(string& tagName);
    XmlElement* tagWithText(string& tagName, string& phrase);
    void getNodes(string tagName, //with no leading or trailng whitespace 
                  size_t number, // the number of such xml elements to collect
                  vector<XmlElement*>* collected);

    
public: //members
    string              _tagName;
    vector<XmlElement*> _children;
    map<string,string>  _attributes;
    string              _text;
}; // end class XmlElement

class Iterator {
public:
    Iterator(XmlElement* node): _node(node), _i(0){}
    
    XmlElement* nextTr();

private:
    //members   
    XmlElement* _node;
    size_t _i;
}; // class iterator

class Parser {
public:
    Parser() {}

    XmlElement* buildXmlTree(string& xmlDocument);
    void parseXML(XmlElement* node, Tokenizer& tok);

    void extract_reports(string& k10, 
                         map<ReportType,string>* extract_reports);
    string extract_quarterly_income(string& page);

    string extractIncomeTableStr(string& incomeStr);

    string extractLatest10kAcn(string& page);
    vector<Acn*> getQuarterAcns(string& page);
    Acn* trToAcn( XmlElement* tr );

    void parseQuarterlyIncomeStatment(XmlElement* tree, 
                                 string& units, string& currency,
                                 string& revenue, string& income, 
                                 double& eps);
    string getUnitsAndCurrency(XmlElement* tree, 
                             string& units, string& currency);
    
    vector<string> titleInfo(XmlElement* tree);
    vector<string> getRevenues(XmlElement* tree);
    vector<string> getIncs(XmlElement* tree);
    vector<float> getEps(XmlElement* tree);
    double getQarterEps(XmlElement* tree);

private:

    XmlTokenType tokenType( string& xml);
    vector<string> getTrByName(XmlElement* tree, string& trTitlePattern);
    XmlElement* edgarResultsTableToTree(string& page);

// members

};

#endif //PARSER





