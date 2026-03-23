/**
 * Copyright (c) 2025 Robert Bosch GmbH.
 *
 * This program and the accompanying materials are made available under the
 * terms of the MIT License which is available at
 * https://opensource.org/licenses/MIT.
 *
 * SPDX-License-Identifier: MIT
 */

#include <iostream>
#include <memory>
#include <string>

#include <grpcpp/grpcpp.h>
#include "val.grpc.pb.h"

using namespace std;
using grpc::Channel;
using grpc::ClientContext;
using grpc::Status;

using kuksa::val::v1::GetRequest;
using kuksa::val::v1::GetResponse;
using kuksa::val::v1::SetRequest;
using kuksa::val::v1::SetResponse;
using kuksa::val::v1::SubscribeRequest;
using kuksa::val::v1::SubscribeResponse;
using kuksa::val::v1::VAL;

class KuksaClient
{
private:
    std::unique_ptr<VAL::Stub> stub_;

public:
    KuksaClient(std::shared_ptr<Channel> channel)
        : stub_(VAL::NewStub(channel)) {}

    void get(const std::string &path)
    {
        GetRequest request;
        GetResponse response;
        ClientContext context;

        auto entry = request.add_entries();
        entry->set_path(path);

        Status status = stub_->Get(&context, request, &response);

        if (!status.ok())
        {
            std::cout << "Get RPC failed: " << status.error_message() << std::endl;
            return;
        }

        for (const auto &e : response.entries())
        {

            std::cout << e.path() << " = ";

            if (e.has_value())
            {

                const auto &v = e.value();

                if (v.has_int32())
                    std::cout << v.int32();
                else if (v.has_uint32())
                    std::cout << v.uint32();
                else if (v.has_float_())
                    std::cout << v.float_();
                else if (v.has_string())
                    std::cout << v.string();
                else
                    std::cout << "Unknown";
            }
            else
            {
                std::cout << "NotAvailable";
            }

            std::cout << std::endl;
        }
    }

    void set(const std::string &path, int value)
    {
        SetRequest request;
        SetResponse response;
        ClientContext context;

        auto update = request.add_updates();
        update->mutable_entry()->set_path(path);
        update->mutable_entry()->mutable_value()->set_int32(value);

        Status status = stub_->Set(&context, request, &response);

        if (!status.ok())
        {
            std::cout << "Set RPC failed: " << status.error_message() << std::endl;
            return;
        }

        std::cout << "Signal updated successfully" << std::endl;
    }

    void subscribe(const std::string &path)
    {
        SubscribeRequest request;
        ClientContext context;

        auto entry = request.add_entries();
        entry->set_path(path);

        auto reader = stub_->Subscribe(&context, request);

        SubscribeResponse response;

        std::cout << "Subscribed to " << path << std::endl;

        while (reader->Read(&response))
        {

            for (const auto &update : response.updates())
            {

                const auto &entry = update.entry();

                std::cout << entry.path() << " = ";

                if (entry.has_value())
                {

                    const auto &v = entry.value();

                    if (v.has_int32())
                        std::cout << v.int32();
                    else if (v.has_uint32())
                        std::cout << v.uint32();
                    else if (v.has_float_())
                        std::cout << v.float_();
                    else if (v.has_string())
                        std::cout << v.string();
                    else
                        std::cout << "Unknown";
                }
                else
                {
                    std::cout << "NotAvailable";
                }

                std::cout << std::endl;
            }
        }
    }
};

const char *kuksa_get_wiper_mode()
{
    static std::string result = "OFF";

    auto channel = grpc::CreateChannel(
        "localhost:55555",
        grpc::InsecureChannelCredentials());

    std::unique_ptr<VAL::Stub> stub = VAL::NewStub(channel);

    GetRequest request;
    GetResponse response;
    ClientContext context;

    auto entry = request.add_entries();
    entry->set_path("Vehicle.Body.Windshield.Front.Wiping.Mode");

    Status status = stub->Get(&context, request, &response);

    if (!status.ok())
        return "OFF";

    for (const auto &e : response.entries())
    {
        if (e.has_value())
        {
            const auto &v = e.value();

            if (v.has_string())
            {
                result = v.string();
                return result.c_str();
            }
        }
    }

    return result.c_str();
}
