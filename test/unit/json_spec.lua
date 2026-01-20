-- Unit tests for json.lua
-- Pure function tests - no mocks needed

-- Add plugin to path
package.path = package.path .. ";./only35.lrplugin/?.lua"

describe("json", function()
    local json = require("json")

    describe("encode", function()
        it("encodes nil as null", function()
            assert.equals("null", json.encode(nil))
        end)

        it("encodes booleans", function()
            assert.equals("true", json.encode(true))
            assert.equals("false", json.encode(false))
        end)

        it("encodes numbers", function()
            assert.equals("42", json.encode(42))
            assert.equals("3.14", json.encode(3.14))
        end)

        it("encodes negative numbers", function()
            assert.equals("-42", json.encode(-42))
            assert.equals("-3.14", json.encode(-3.14))
        end)

        it("encodes strings", function()
            assert.equals('"hello"', json.encode("hello"))
        end)

        it("encodes strings with escape characters", function()
            local result = json.encode("line\nbreak")
            assert.truthy(result:match("\\n"))
        end)

        it("encodes strings with quotes", function()
            local result = json.encode('say "hello"')
            assert.truthy(result:match('\\"'))
        end)

        it("encodes empty array", function()
            local result = json.encode({})
            assert.truthy(result == "[]" or result == "{}")
        end)

        it("encodes arrays", function()
            local result = json.encode({1, 2, 3})
            assert.truthy(result:match("%["))
            assert.truthy(result:match("1"))
            assert.truthy(result:match("2"))
            assert.truthy(result:match("3"))
        end)

        it("encodes objects", function()
            local result = json.encode({name = "test"})
            assert.truthy(result:match('"name"'))
            assert.truthy(result:match('"test"'))
        end)

        it("encodes nested structures", function()
            local data = {
                data = {
                    type = "photographs",
                    attributes = { name = "photo.jpg" }
                }
            }
            local result = json.encode(data)
            assert.truthy(result:match('"type"'))
            assert.truthy(result:match('"photographs"'))
            assert.truthy(result:match('"attributes"'))
        end)

        it("encodes JSON:API style payload", function()
            local payload = {
                data = {
                    id = "123",
                    type = "photographs",
                    attributes = {
                        stars = 5,
                        selected = true,
                        description = "A beautiful photo"
                    }
                }
            }
            local result = json.encode(payload)
            assert.truthy(result:match('"id"'))
            assert.truthy(result:match('"123"'))
            assert.truthy(result:match('"stars"'))
        end)
    end)

    describe("decode", function()
        it("decodes null to nil", function()
            assert.is_nil(json.decode("null"))
        end)

        it("decodes true", function()
            assert.equals(true, json.decode("true"))
        end)

        it("decodes false", function()
            assert.equals(false, json.decode("false"))
        end)

        it("decodes positive integers", function()
            assert.equals(42, json.decode("42"))
        end)

        it("decodes negative integers", function()
            assert.equals(-42, json.decode("-42"))
        end)

        it("decodes floating point numbers", function()
            assert.equals(3.14, json.decode("3.14"))
            assert.equals(-3.14, json.decode("-3.14"))
        end)

        it("decodes simple strings", function()
            assert.equals("hello", json.decode('"hello"'))
        end)

        it("decodes empty string", function()
            assert.equals("", json.decode('""'))
        end)

        it("decodes empty array", function()
            local result = json.decode("[]")
            assert.is_table(result)
            assert.equals(0, #result)
        end)

        it("decodes array of numbers", function()
            local result = json.decode("[1,2,3]")
            assert.equals(3, #result)
            assert.equals(1, result[1])
            assert.equals(2, result[2])
            assert.equals(3, result[3])
        end)

        it("decodes array of strings", function()
            local result = json.decode('["a","b","c"]')
            assert.equals(3, #result)
            assert.equals("a", result[1])
        end)

        it("decodes empty object", function()
            local result = json.decode("{}")
            assert.is_table(result)
        end)

        it("decodes simple object", function()
            local result = json.decode('{"name":"test"}')
            assert.equals("test", result.name)
        end)

        it("decodes object with multiple properties", function()
            local result = json.decode('{"name":"test","value":42}')
            assert.equals("test", result.name)
            assert.equals(42, result.value)
        end)

        it("decodes nested objects", function()
            local result = json.decode('{"outer":{"inner":"value"}}')
            assert.equals("value", result.outer.inner)
        end)

        it("roundtrips complex JSON:API structure", function()
            local original = {
                data = {
                    id = "123",
                    type = "photographs",
                    attributes = { stars = 5 }
                }
            }
            local encoded = json.encode(original)
            local decoded = json.decode(encoded)
            assert.equals("123", decoded.data.id)
            assert.equals("photographs", decoded.data.type)
            assert.equals(5, decoded.data.attributes.stars)
        end)

        it("handles empty input gracefully", function()
            assert.is_nil(json.decode(""))
        end)

        it("handles nil input gracefully", function()
            assert.is_nil(json.decode(nil))
        end)

        it("handles whitespace around values", function()
            assert.equals(42, json.decode("  42  "))
            assert.equals("test", json.decode('  "test"  '))
        end)
    end)

    describe("roundtrip", function()
        it("preserves boolean values", function()
            assert.equals(true, json.decode(json.encode(true)))
            assert.equals(false, json.decode(json.encode(false)))
        end)

        it("preserves numeric values", function()
            assert.equals(42, json.decode(json.encode(42)))
            assert.equals(3.14, json.decode(json.encode(3.14)))
        end)

        it("preserves string values", function()
            assert.equals("hello world", json.decode(json.encode("hello world")))
        end)

        it("preserves array structure", function()
            local original = {1, 2, 3, 4, 5}
            local result = json.decode(json.encode(original))
            assert.equals(5, #result)
            for i = 1, 5 do
                assert.equals(i, result[i])
            end
        end)
    end)
end)
