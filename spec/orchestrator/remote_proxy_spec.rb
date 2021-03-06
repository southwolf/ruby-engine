require 'rails'
require 'orchestrator'
require File.expand_path("../helpers", __FILE__)


class MockCtrl
    def initialize(logger, do_fail = false)
        @log = logger
        @do_fail = do_fail
    end

    def start(mod, remote = true)
        defer = ::Libuv.reactor.defer
        @log << [:start, mod, remote]
        @do_fail ? defer.reject(false) : defer.resolve(true)
        defer.promise
    end

    def stop(mod, remote = true)
        defer = ::Libuv.reactor.defer
        @log << [:stop, mod, remote]
        @do_fail ? defer.reject(false) : defer.resolve(true)
        defer.promise
    end

    def unload(mod, remote = true)
        defer = ::Libuv.reactor.defer
        @log << [:unload, mod, remote]
        @do_fail ? defer.reject(false) : defer.resolve(true)
        defer.promise
    end

    def loaded?(mod_name)
        self unless @do_fail
    end

    def update(mod, remote = true)
        defer = ::Libuv.reactor.defer
        @log << [:update, mod, remote]
        @do_fail ? defer.reject(false) : defer.resolve(true)
        defer.promise
    end

    def expire_cache(sys, remote = true, no_update: nil)
        @log << [:expire_cache, sys, remote]
    end

    def reactor
        ::Libuv.reactor
    end

    # ===============
    # This is emulating a module manager for status requests
    # ===============
    def status
        {
            connected: true
        }
    end

    def trak(status, val, remote = true)
        @log << [status, val, remote]
        val
    end

    # ===============
    # This is technically the dependency manager
    # ===============
    def load(dependency, force = false)
        defer = ::Libuv.reactor.defer
        classname = dependency.class_name
        class_object = classname.constantize

        defer.resolve(class_object)
        defer.promise
    end

    # this is technically the TCP object
    def write(data)
        written = ::JSON.parse(data[1..-2], symbolize_names: true)
        @log << written
        ::Libuv::Q::ResolvedPromise.new(::Libuv.reactor, written)
    end

    def finally
    end
end


describe Orchestrator::Remote::Proxy do
    before :each do
        @reactor = ::Libuv::Reactor.default
        @log = []
    end

    it "should send an execute request" do
        failed = true
        @reactor.run do
            mock = MockCtrl.new(@log, true)
            proxy = ::Orchestrator::Remote::Proxy.new(mock, mock, mock)

            # Create request
            req = proxy.execute('mod_111', 'function', [1,2,3])
            expect(@log[0]).to eq({
                type: 'cmd',
                mod: 'mod_111',
                func: 'function',
                args: [1,2,3],
                id: '1'
            })

            # Process request
            proxy.process(@log[0])
            expect(@log[1][:id]).to eq('1')
            expect(@log[1][:type]).to eq('resp')
            expect(@log[1][:reject]).to eq('module not loaded')

            # Process response
            proxy.process(@log[1])
            req.catch do |error|
                failed = false
            end
        end

        expect(failed).to be(false)
    end

    it "should send a status lookup request" do
        failed = true
        @reactor.run do
            mock = MockCtrl.new(@log)
            proxy = ::Orchestrator::Remote::Proxy.new(mock, mock, mock)

            # Create request
            req = proxy.status('mod_111', 'connected')
            expect(@log[0]).to eq({
                type: 'stat',
                mod: 'mod_111',
                stat: 'connected',
                id: '1'
            })

            # Process request
            proxy.process(@log[0])
            expect(@log[1][:id]).to eq('1')
            expect(@log[1][:type]).to eq('resp')
            expect(@log[1][:resolve]).to eq(true)

            # Process response
            proxy.process(@log[1])
            req.then do |resp|
                failed = resp != true
            end
        end

        expect(failed).to be(false)
    end

    it "should send a set status request" do
        failed = true
        @reactor.run do
            mock = MockCtrl.new(@log)
            proxy = ::Orchestrator::Remote::Proxy.new(mock, mock, mock)

            # Create request
            req = proxy.set_status('mod_111', 'new_status', 'value')
            expect(@log[0]).to eq({
                type: 'push',
                push: 'status',
                mod: 'mod_111',
                stat: 'new_status',
                val: 'value',
                id: '1'
            })

            # Process request
            proxy.process(@log[0])
            expect(@log[1]).to eq([:new_status, 'value', false])

            expect(@log[2][:id]).to eq('1')
            expect(@log[2][:type]).to eq('resp')
            expect(@log[2][:resolve]).to eq(true)

            # Process response
            proxy.process(@log[2])
            req.then do |resp|
                failed = resp != true
            end
        end

        expect(failed).to be(false)
    end

    it "should fail to send a set status request" do
        failed = true
        @reactor.run do
            mock = MockCtrl.new(@log)
            proxy = ::Orchestrator::Remote::Proxy.new(mock, mock, mock)

            # Create request
            req = proxy.set_status('mod_111', 'new_status', Object.new)
            expect(@log[0]).to be(nil)

            req.catch do |error|
                failed = false
            end
        end

        expect(failed).to be(false)
    end

    it "should send a start module request" do
        failed = true
        @reactor.run do
            mock = MockCtrl.new(@log)
            proxy = ::Orchestrator::Remote::Proxy.new(mock, mock, mock)

            # Create request
            req = proxy.start('mod_111')
            expect(@log[0]).to eq({
                type: 'push',
                push: 'start',
                mod: 'mod_111',
                id: '1'
            })

            # Process request
            proxy.process(@log[0])
            @reactor.next_tick do
                expect(@log[1]).to eq([:start, 'mod_111', false])

                expect(@log[2][:id]).to eq('1')
                expect(@log[2][:type]).to eq('resp')
                expect(@log[2][:resolve]).to eq(true)

                # Process response
                proxy.process(@log[2])
                req.then do |resp|
                    failed = resp != true
                end
            end
        end

        expect(failed).to be(false)
    end

    it "should send a stop module request" do
        failed = true
        @reactor.run do
            mock = MockCtrl.new(@log)
            proxy = ::Orchestrator::Remote::Proxy.new(mock, mock, mock)

            # Create request
            req = proxy.stop('mod_111')
            expect(@log[0]).to eq({
                type: 'push',
                push: 'stop',
                mod: 'mod_111',
                id: '1'
            })

            # Process request
            proxy.process(@log[0])
            @reactor.next_tick do
                expect(@log[1]).to eq([:stop, 'mod_111', false])

                expect(@log[2][:id]).to eq('1')
                expect(@log[2][:type]).to eq('resp')
                expect(@log[2][:resolve]).to eq(true)

                # Process response
                proxy.process(@log[2])
                req.then do |resp|
                    failed = resp != true
                end
            end
        end

        expect(failed).to be(false)
    end

    it "should send a load module request" do
        failed = true
        @reactor.run do
            mock = MockCtrl.new(@log)
            proxy = ::Orchestrator::Remote::Proxy.new(mock, mock, mock)

            # Create request
            req = proxy.load('mod_111')
            expect(@log[0]).to eq({
                type: 'push',
                push: 'load',
                mod: 'mod_111',
                id: '1'
            })

            # Process request
            proxy.process(@log[0])
            @reactor.next_tick do
                expect(@log[1]).to eq([:update, 'mod_111', false])

                expect(@log[2][:id]).to eq('1')
                expect(@log[2][:type]).to eq('resp')
                expect(@log[2][:resolve]).to eq(true)

                # Process response
                proxy.process(@log[2])
                req.then do |resp|
                    failed = resp != true
                end
            end
        end

        expect(failed).to be(false)
    end

    it "should send an unload module request" do
        failed = true
        @reactor.run do
            mock = MockCtrl.new(@log)
            proxy = ::Orchestrator::Remote::Proxy.new(mock, mock, mock)

            # Create request
            req = proxy.unload('mod_111')
            expect(@log[0]).to eq({
                type: 'push',
                push: 'unload',
                mod: 'mod_111',
                id: '1'
            })

            # Process request
            proxy.process(@log[0])
            @reactor.next_tick do
                expect(@log[1]).to eq([:unload, 'mod_111', false])

                expect(@log[2][:id]).to eq('1')
                expect(@log[2][:type]).to eq('resp')
                expect(@log[2][:resolve]).to eq(true)

                # Process response
                proxy.process(@log[2])
                req.then do |resp|
                    failed = resp != true
                end
            end
        end

        expect(failed).to be(false)
    end

    it "should send a reload module request - failure response" do
        failed = true
        @reactor.run do
            mock = MockCtrl.new(@log)
            proxy = ::Orchestrator::Remote::Proxy.new(mock, mock, mock)

            # Create request
            req = proxy.reload('dep_111')
            expect(@log[0]).to eq({
                type: 'push',
                push: 'reload',
                dep: 'dep_111',
                id: '1'
            })

            # Process request
            proxy.process(@log[0])
            @reactor.next_tick do
                expect(@log[1][:id]).to eq('1')
                expect(@log[1][:type]).to eq('resp')
                expect(@log[1][:reject]).to eq('dependency dep_111 not found')

                # Process response
                proxy.process(@log[1])
                req.catch do |error|
                    failed = false
                end
            end
        end

        expect(failed).to be(false)
    end

    it "should send an expire cache request" do
        failed = true
        @reactor.run do
            begin
                mock = MockCtrl.new(@log)
                proxy = ::Orchestrator::Remote::Proxy.new(mock, mock, mock)

                zone = ::Orchestrator::Zone.new
                zone.name = 'test zone'
                zone.save!

                cs = ::Orchestrator::ControlSystem.new
                cs.name = 'testing cache expiry...'
                cs.edge_id = ::Orchestrator::Remote::NodeId
                cs.zones << zone.id
                begin
                    cs.save!
                rescue => e
                    puts "#{cs.errors.inspect}"
                    raise e
                end

                # Create request
                req = proxy.expire_cache(cs.id)
                expect(@log[0]).to eq({
                    type: 'expire',
                    sys: cs.id,
                    id: '1'
                })

                # Process request
                proxy.process(@log[0])
                expect(@log[1]).to eq([:expire_cache, cs.id, false])

                expect(@log[2][:id]).to eq('1')
                expect(@log[2][:type]).to eq('resp')
                expect(@log[2][:resolve]).to eq(true)

                # Process response
                proxy.process(@log[2])
                req.then do |resp|
                    failed = resp != true
                end
            ensure
                cs.destroy
                zone.destroy
            end
        end

        expect(failed).to be(false)
    end
end
