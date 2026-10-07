import AppKit
func runSelfTests() throws {
    func check(_ v:Bool,_ message:String) throws {if !v {throw AppFailure(message)}}
    let config=Settings(); let encoded=try JSONEncoder().encode(config);let decoded=try JSONDecoder().decode(Settings.self,from:encoded)
    try check(decoded.shortcuts==Shortcut.defaults,"Settings roundtrip")
    for provider in Provider.allCases {
        let body=ModelClient.body(provider:provider,model:provider.models[0],instruction:"instruction",text:"question",images:[Data([1,2,3])],schema:regionSchema)
        let d=try JSONSerialization.data(withJSONObject:body);let string=String(data:d,encoding:.utf8)!
        try check(string.contains("AQID"),"Image missing from \(provider)")
        try check(!string.contains("Bearer"),"Credentials in body")
        if provider == .openAI {try check(body["input"] != nil && body["messages"]==nil,"OpenAI transport");try check(body["store"] as? Bool == false,"No storage flag")}
        else {try check(body["messages"] != nil && body["response_format"] != nil,"Chat schema for \(provider)")}
    }
    let response:[String:Any]=["status":"completed","output":[["content":[["type":"output_text","text":"B — 42"]]]]]
    let answer=try ModelClient.parse(response,provider:.openAI);try check(answer=="B — 42","OpenAI response")
    for p in Provider.allCases where p != .openAI {let a=try ModelClient.parse(["choices":[["finish_reason":"stop","message":["content":"Answer"]]]],provider:p);try check(a=="Answer","Chat response")}
    var rejected=false;do {_ = try ModelClient.parse(["status":"incomplete"],provider:.openAI)}catch{rejected=true};try check(rejected,"Incomplete not rejected")
    rejected=false;do {_ = try ModelClient.parse(["output":[["content":[["type":"refusal","refusal":"No"]]]]],provider:.openAI)}catch{rejected=true};try check(rejected,"Refusal not surfaced")
    for p in Provider.allCases {
        rejected=false;do {_ = try ModelClient.parse([:],provider:p)}catch{rejected=true};try check(rejected,"Empty response accepted for \(p)")
    }
    rejected=false;do {_ = try ModelClient.parse(["choices":[["finish_reason":"length","message":["content":"partial"]]]],provider:.groq)}catch{rejected=true};try check(rejected,"Truncated chat response accepted")
    let context=CGContext(data:nil,width:200,height:100,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.red.cgColor);context.fill(CGRect(x:0,y:0,width:200,height:100));let image=context.makeImage()!
    let region=Region(x:0.25,y:0.25,width:0.5,height:0.5);let rect=try region.rect(in:image);try check(rect.width>100 && rect.width<120 && rect.height>50,"Region conversion")
    let jpeg=try ScreenCapture.jpeg(image);try check(jpeg.starts(with:[0xff,0xd8]),"JPEG encoding")
    rejected=false;do {_ = try Region(x:-1,y:0,width:1,height:1).rect(in:image)}catch{rejected=true};try check(rejected,"Bad crop accepted")
    let selection=try JSONDecoder().decode(Detection.self,from:Data("{\"found\":false,\"region\":null}".utf8));try check(!selection.found && selection.region==nil,"Empty detection")
    try check(Set(Shortcut.defaults.map{"\($0.key):\($0.modifiers)"}).count==6,"Shortcut collision")
}
